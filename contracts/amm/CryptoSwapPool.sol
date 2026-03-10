// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/ICryptoSwapPool.sol";
import "./libraries/TickMath.sol";
import "./libraries/SqrtPriceMath.sol";
import "./libraries/LiquidityMath.sol";

/**
 * @notice Callback interface for swap callers.
 * The pool uses a "callback" pattern:
 * 1. Pool calculates the swap and sends output tokens
 * 2. Pool calls back to the sender to collect input tokens
 * 3. Pool verifies it received the right amount
 *
 * This pattern is used in Uniswap V3 for atomic, flash-swap style trades.
 */
interface ICryptoSwapCallback {
    function cryptoSwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external;
}

interface ICryptoSwapMintCallback {
    function cryptoSwapMintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external;
}

/**
 * @title CryptoSwapPool
 * @author Prakash Yadav
 * @notice A single trading pool for a specific token pair and fee tier.
 *
 * ═══════════════════════════════════════════════════════
 * 📚 LEARNING: THE POOL IS THE HEART OF THE AMM
 * ═══════════════════════════════════════════════════════
 *
 * This contract:
 * 1. HOLDS the token reserves (the actual tokens)
 * 2. PRICES swaps using the constant product formula
 * 3. MANAGES liquidity positions (LPs deposit/withdraw)
 * 4. COLLECTS fees from every swap
 *
 * SIMPLIFIED FLOW:
 *
 *   User wants to swap 1 ETH → USDC:
 *   ┌──────────┐    1 ETH     ┌──────────┐
 *   │  User    │ ────────────►│   Pool   │
 *   │          │◄──────────── │          │
 *   └──────────┘   2800 USDC  └──────────┘
 *
 *   The pool uses x*y=k to calculate how much USDC to give:
 *   - Before: 100 ETH * 280,000 USDC = 28,000,000 (k)
 *   - After:  101 ETH * ?         USDC = 28,000,000
 *   - ?     = 28,000,000 / 101 = 277,227.72 USDC
 *   - Output = 280,000 - 277,227.72 = 2,772.28 USDC
 *   - Minus 0.30% fee = 2,763.97 USDC
 *
 * CONCENTRATED LIQUIDITY:
 *   Instead of spreading liquidity across ALL prices,
 *   LPs choose a range. This contract tracks which liquidity
 *   is "active" at the current price (tick).
 * ═══════════════════════════════════════════════════════
 */
contract CryptoSwapPool is ICryptoSwapPool, ReentrancyGuard {
    // ═══════════════════════════════════════
    //  State Variables
    // ═══════════════════════════════════════

    /// @notice The factory that created this pool
    address public factory;

    /// @notice Token addresses (sorted: token0 < token1)
    address public override token0;
    address public override token1;

    /// @notice Fee tier in hundredths of a basis point
    uint24 public override fee;

    /// @notice Tick spacing for this fee tier
    int24 public tickSpacing;

    // ---- Slot0: packed for gas efficiency ----
    /// @notice Current sqrt price as Q64.96
    uint160 public override sqrtPriceX96;
    /// @notice Current tick (derived from sqrtPriceX96)
    int24 public override tick;
    /// @notice Whether the pool has been initialized
    bool public initialized;

    /// @notice Current total active liquidity
    uint128 public override liquidity;

    /// @notice Global fee growth per unit of liquidity (token0)
    uint256 public feeGrowthGlobal0X128;
    /// @notice Global fee growth per unit of liquidity (token1)
    uint256 public feeGrowthGlobal1X128;

    /// @notice Protocol fees collected (token0)
    uint128 public protocolFees0;
    /// @notice Protocol fees collected (token1)
    uint128 public protocolFees1;

    // ---- Position tracking ----

    /**
     * @notice A position represents a liquidity provider's deposit.
     *
     * EXAMPLE: Alice provides liquidity in ETH/USDC from tick -100 to tick +100:
     *   Position {
     *     liquidity: 50000,        // How much liquidity she provided
     *     feeGrowthInside0Last: 0, // Snapshot of fee growth when she entered
     *     feeGrowthInside1Last: 0, // (used to calculate her earned fees)
     *     tokensOwed0: 0,          // Uncollected fees in token0
     *     tokensOwed1: 0           // Uncollected fees in token1
     *   }
     */
    struct Position {
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    /// @notice All positions: key = keccak256(owner, tickLower, tickUpper)
    mapping(bytes32 => Position) public positions;

    /**
     * @notice Tick data tracks liquidity changes at each tick boundary.
     *
     * WHEN DOES THIS MATTER?
     * - During a swap, if the price crosses a tick boundary,
     *   we need to add/remove the liquidity that starts/ends at that tick
     * - liquidityNet: positive = liquidity added when crossing left-to-right
     *                 negative = liquidity removed
     */
    struct TickInfo {
        uint128 liquidityGross;     // Total liquidity referencing this tick
        int128 liquidityNet;        // Net liquidity change when crossing
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
        bool initialized;
    }

    /// @notice Tick data for each initialized tick
    mapping(int24 => TickInfo) public ticks;

    // ═══════════════════════════════════════
    //  Swap State Structs (to avoid stack-too-deep)
    // ═══════════════════════════════════════

    /**
     * 📚 WHY STRUCTS?
     * The EVM only allows 16 local variables on the stack.
     * Complex functions like swap() need more variables.
     * By packing them into a struct (stored in memory), we bypass this limit.
     */
    struct SwapState {
        int256 amountSpecifiedRemaining;
        int256 amountCalculated;
        uint160 sqrtPriceX96;
        int24 tick;
        uint128 liquidity;
    }

    struct StepResult {
        uint160 sqrtPriceNext;
        uint256 amountIn;
        uint256 amountOut;
        uint256 feeAmount;
    }

    // ═══════════════════════════════════════
    //  Constructor
    // ═══════════════════════════════════════

    constructor(
        address _factory,
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickSpacing
    ) {
        factory = _factory;
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        tickSpacing = _tickSpacing;
    }

    // ═══════════════════════════════════════
    //  Initialize
    // ═══════════════════════════════════════

    /**
     * @notice Initialize the pool with a starting price.
     * @param _sqrtPriceX96 The initial sqrt price
     *
     * 📚 IMPORTANT: A pool MUST be initialized before any swaps or liquidity.
     *
     * HOW TO CALCULATE sqrtPriceX96:
     *   If 1 token0 = 3000 token1 (like 1 ETH = 3000 USDC):
     *   sqrtPriceX96 = sqrt(3000) * 2^96 ≈ 4339505179874779489431521
     *
     *   Quick formula: sqrtPriceX96 = sqrt(price) * 2^96
     */
    function initialize(uint160 _sqrtPriceX96) external override {
        require(!initialized, "AI"); // Already Initialized

        sqrtPriceX96 = _sqrtPriceX96;
        tick = TickMath.getTickAtSqrtRatio(_sqrtPriceX96);
        initialized = true;
    }

    // ═══════════════════════════════════════
    //  Swap
    // ═══════════════════════════════════════

    /**
     * @notice Execute a token swap.
     * @param recipient Who receives the output tokens
     * @param zeroForOne Direction: true = token0→token1, false = token1→token0
     * @param amountSpecified How much to swap (positive = exact input, negative = exact output)
     * @param _sqrtPriceLimitX96 Price limit to prevent excessive slippage
     * @param data Callback data
     *
     * 📚 SWAP STEP BY STEP:
     * 1. Validate inputs
     * 2. Compute swap step (how much can be swapped at current liquidity)
     * 3. Update state (price, liquidity, fees)
     * 4. Transfer output tokens to recipient
     * 5. Call back to sender to collect input tokens
     * 6. Verify the pool received the correct input amount
     */
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 _sqrtPriceLimitX96,
        bytes calldata data
    ) external override nonReentrant returns (int256 amount0, int256 amount1) {
        require(initialized, "NI"); // Not Initialized
        require(amountSpecified != 0, "AS");

        // Validate price limit
        if (zeroForOne) {
            require(
                _sqrtPriceLimitX96 < sqrtPriceX96 &&
                _sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO,
                "SPL"
            );
        } else {
            require(
                _sqrtPriceLimitX96 > sqrtPriceX96 &&
                _sqrtPriceLimitX96 < TickMath.MAX_SQRT_RATIO,
                "SPL"
            );
        }

        bool exactInput = amountSpecified > 0;

        // Pack state into struct to avoid stack-too-deep
        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            liquidity: liquidity
        });

        // Compute the swap step
        if (state.liquidity > 0) {
            StepResult memory step = _computeSwapStep(
                state, zeroForOne, exactInput, _sqrtPriceLimitX96
            );

            // Update fee growth
            if (zeroForOne) {
                feeGrowthGlobal0X128 += (step.feeAmount << 128) / state.liquidity;
            } else {
                feeGrowthGlobal1X128 += (step.feeAmount << 128) / state.liquidity;
            }

            // Update remaining amounts
            if (exactInput) {
                state.amountSpecifiedRemaining -= int256(step.amountIn + step.feeAmount);
                state.amountCalculated -= int256(step.amountOut);
            } else {
                state.amountSpecifiedRemaining += int256(step.amountOut);
                state.amountCalculated += int256(step.amountIn + step.feeAmount);
            }

            state.sqrtPriceX96 = step.sqrtPriceNext;
            state.tick = TickMath.getTickAtSqrtRatio(step.sqrtPriceNext);
        }

        // Update storage state
        sqrtPriceX96 = state.sqrtPriceX96;
        tick = state.tick;

        // Calculate final amounts
        (amount0, amount1) = _computeFinalAmounts(
            zeroForOne, exactInput, amountSpecified, state
        );

        // Transfer and verify
        _transferAndVerify(recipient, zeroForOne, amount0, amount1, data);

        emit Swap(msg.sender, recipient, amount0, amount1, sqrtPriceX96, liquidity, tick);
    }

    /**
     * @dev Compute a single swap step: next price, amounts in/out, and fees.
     */
    function _computeSwapStep(
        SwapState memory state,
        bool zeroForOne,
        bool exactInput,
        uint160 sqrtPriceLimitX96_
    ) internal view returns (StepResult memory step) {
        uint256 absAmount = state.amountSpecifiedRemaining > 0
            ? uint256(state.amountSpecifiedRemaining)
            : uint256(-state.amountSpecifiedRemaining);

        // Calculate fee
        step.feeAmount = (absAmount * fee) / 1000000;
        uint256 amountAfterFee = absAmount - step.feeAmount;

        // Compute next sqrt price
        if (exactInput) {
            step.sqrtPriceNext = zeroForOne
                ? SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(
                    state.sqrtPriceX96, state.liquidity, amountAfterFee, true)
                : SqrtPriceMath.getNextSqrtPriceFromAmount1RoundingDown(
                    state.sqrtPriceX96, state.liquidity, amountAfterFee, true);
        } else {
            step.sqrtPriceNext = zeroForOne
                ? SqrtPriceMath.getNextSqrtPriceFromAmount1RoundingDown(
                    state.sqrtPriceX96, state.liquidity, absAmount, false)
                : SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(
                    state.sqrtPriceX96, state.liquidity, absAmount, false);
        }

        // Apply price limit
        if (zeroForOne && step.sqrtPriceNext < sqrtPriceLimitX96_) {
            step.sqrtPriceNext = sqrtPriceLimitX96_;
        } else if (!zeroForOne && step.sqrtPriceNext > sqrtPriceLimitX96_) {
            step.sqrtPriceNext = sqrtPriceLimitX96_;
        }

        // Calculate actual amounts
        step.amountIn = SqrtPriceMath.getAmount0Delta(
            state.sqrtPriceX96, step.sqrtPriceNext, state.liquidity, zeroForOne
        );
        step.amountOut = SqrtPriceMath.getAmount1Delta(
            state.sqrtPriceX96, step.sqrtPriceNext, state.liquidity, !zeroForOne
        );

        if (!zeroForOne) {
            (step.amountIn, step.amountOut) = (step.amountOut, step.amountIn);
        }
    }

    /**
     * @dev Calculate final amount0 and amount1 from swap state.
     */
    function _computeFinalAmounts(
        bool zeroForOne,
        bool exactInput,
        int256 amountSpecified,
        SwapState memory state
    ) internal pure returns (int256 amount0, int256 amount1) {
        if (exactInput) {
            amount0 = zeroForOne
                ? amountSpecified - state.amountSpecifiedRemaining
                : state.amountCalculated;
            amount1 = zeroForOne
                ? state.amountCalculated
                : amountSpecified - state.amountSpecifiedRemaining;
        } else {
            amount0 = zeroForOne
                ? state.amountCalculated
                : amountSpecified - state.amountSpecifiedRemaining;
            amount1 = zeroForOne
                ? amountSpecified - state.amountSpecifiedRemaining
                : state.amountCalculated;
        }
    }

    /**
     * @dev Transfer output tokens and verify input tokens via callback.
     */
    function _transferAndVerify(
        address recipient,
        bool zeroForOne,
        int256 amount0,
        int256 amount1,
        bytes calldata data
    ) internal {
        // Transfer output tokens
        if (zeroForOne && amount1 < 0) {
            IERC20(token1).transfer(recipient, uint256(-amount1));
        } else if (!zeroForOne && amount0 < 0) {
            IERC20(token0).transfer(recipient, uint256(-amount0));
        }

        // Callback to collect input tokens
        uint256 balance0Before = IERC20(token0).balanceOf(address(this));
        uint256 balance1Before = IERC20(token1).balanceOf(address(this));

        ICryptoSwapCallback(msg.sender).cryptoSwapCallback(amount0, amount1, data);

        // Verify we received the input tokens
        if (amount0 > 0) {
            require(
                IERC20(token0).balanceOf(address(this)) >= balance0Before + uint256(amount0),
                "IIA0"
            );
        }
        if (amount1 > 0) {
            require(
                IERC20(token1).balanceOf(address(this)) >= balance1Before + uint256(amount1),
                "IIA1"
            );
        }
    }

    // ═══════════════════════════════════════
    //  Mint (Add Liquidity)
    // ═══════════════════════════════════════

    /**
     * @notice Add liquidity to a specific price range.
     * @param recipient Owner of the position
     * @param tickLower Lower bound of the price range
     * @param tickUpper Upper bound of the price range
     * @param amount Amount of liquidity to add
     * @param data Callback data
     *
     * 📚 HOW ADDING LIQUIDITY WORKS:
     * 1. LP chooses a price range [tickLower, tickUpper]
     * 2. LP deposits the right ratio of tokens for that range
     * 3. LP earns fees from swaps that occur within their range
     * 4. If price moves outside their range, they stop earning fees
     *
     * TOKEN AMOUNTS:
     * - If current price is WITHIN the range → need both tokens
     * - If current price is BELOW the range → need only token0
     * - If current price is ABOVE the range → need only token1
     */
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external override nonReentrant returns (uint256 amount0, uint256 amount1) {
        require(initialized, "NI");
        require(amount > 0, "AM");
        require(tickLower < tickUpper, "TLU");
        require(tickLower >= TickMath.MIN_TICK, "TLM");
        require(tickUpper <= TickMath.MAX_TICK, "TUM");
        // Ensure ticks are on valid spacing
        require(tickLower % tickSpacing == 0, "TLS");
        require(tickUpper % tickSpacing == 0, "TUS");

        // Calculate how many tokens the LP needs to deposit
        if (tick < tickLower) {
            // Current price is below range: need only token0
            amount0 = SqrtPriceMath.getAmount0Delta(
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                amount,
                true
            );
        } else if (tick < tickUpper) {
            // Current price is within range: need both tokens
            amount0 = SqrtPriceMath.getAmount0Delta(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(tickUpper),
                amount,
                true
            );
            amount1 = SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtRatioAtTick(tickLower),
                sqrtPriceX96,
                amount,
                true
            );

            // Add to active liquidity (price is in range)
            liquidity = LiquidityMath.addDelta(liquidity, int128(amount));
        } else {
            // Current price is above range: need only token1
            amount1 = SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                amount,
                true
            );
        }

        // Update tick data
        _updateTick(tickLower, int128(amount));
        _updateTick(tickUpper, -int128(amount));

        // Update position
        bytes32 positionKey = keccak256(abi.encodePacked(recipient, tickLower, tickUpper));
        Position storage position = positions[positionKey];
        position.liquidity += amount;

        // Callback to collect tokens from user
        uint256 balance0Before = IERC20(token0).balanceOf(address(this));
        uint256 balance1Before = IERC20(token1).balanceOf(address(this));

        ICryptoSwapMintCallback(msg.sender).cryptoSwapMintCallback(amount0, amount1, data);

        // Verify tokens received
        if (amount0 > 0) {
            require(
                IERC20(token0).balanceOf(address(this)) >= balance0Before + amount0,
                "M0" // Mint: insufficient token0
            );
        }
        if (amount1 > 0) {
            require(
                IERC20(token1).balanceOf(address(this)) >= balance1Before + amount1,
                "M1" // Mint: insufficient token1
            );
        }

        emit Mint(msg.sender, recipient, tickLower, tickUpper, amount, amount0, amount1);
    }

    // ═══════════════════════════════════════
    //  Burn (Remove Liquidity)
    // ═══════════════════════════════════════

    /**
     * @notice Remove liquidity from a position.
     * @param tickLower Lower tick of the position
     * @param tickUpper Upper tick of the position
     * @param amount Amount of liquidity to remove
     *
     * 📚 This doesn't transfer tokens — it "unlocks" them.
     *    Call collect() afterwards to actually receive the tokens.
     *    This two-step process prevents reentrancy attacks.
     */
    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external override nonReentrant returns (uint256 amount0, uint256 amount1) {
        bytes32 positionKey = keccak256(abi.encodePacked(msg.sender, tickLower, tickUpper));
        Position storage position = positions[positionKey];

        require(amount <= position.liquidity, "BL");

        // Calculate tokens to return
        if (tick < tickLower) {
            amount0 = SqrtPriceMath.getAmount0Delta(
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                amount,
                false
            );
        } else if (tick < tickUpper) {
            amount0 = SqrtPriceMath.getAmount0Delta(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(tickUpper),
                amount,
                false
            );
            amount1 = SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtRatioAtTick(tickLower),
                sqrtPriceX96,
                amount,
                false
            );

            liquidity = LiquidityMath.addDelta(liquidity, -int128(amount));
        } else {
            amount1 = SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                amount,
                false
            );
        }

        // Update position
        position.liquidity -= amount;
        position.tokensOwed0 += uint128(amount0);
        position.tokensOwed1 += uint128(amount1);

        // Update tick data
        _updateTick(tickLower, -int128(amount));
        _updateTick(tickUpper, int128(amount));

        emit Burn(msg.sender, tickLower, tickUpper, amount, amount0, amount1);
    }

    // ═══════════════════════════════════════
    //  Collect (Withdraw tokens/fees)
    // ═══════════════════════════════════════

    /**
     * @notice Collect tokens owed to a position (from burns + earned fees).
     */
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external override nonReentrant returns (uint128 amount0, uint128 amount1) {
        bytes32 positionKey = keccak256(abi.encodePacked(msg.sender, tickLower, tickUpper));
        Position storage position = positions[positionKey];

        amount0 = amount0Requested > position.tokensOwed0
            ? position.tokensOwed0
            : amount0Requested;
        amount1 = amount1Requested > position.tokensOwed1
            ? position.tokensOwed1
            : amount1Requested;

        if (amount0 > 0) {
            position.tokensOwed0 -= amount0;
            IERC20(token0).transfer(recipient, amount0);
        }
        if (amount1 > 0) {
            position.tokensOwed1 -= amount1;
            IERC20(token1).transfer(recipient, amount1);
        }
    }

    // ═══════════════════════════════════════
    //  Internal Helpers
    // ═══════════════════════════════════════

    function _updateTick(int24 _tick, int128 liquidityDelta) internal {
        TickInfo storage info = ticks[_tick];
        uint128 liquidityGrossBefore = info.liquidityGross;
        uint128 liquidityGrossAfter = LiquidityMath.addDelta(liquidityGrossBefore, liquidityDelta);

        if (liquidityGrossBefore == 0 && liquidityGrossAfter > 0) {
            info.initialized = true;
        }

        info.liquidityGross = liquidityGrossAfter;
        info.liquidityNet = info.liquidityNet + liquidityDelta;
    }

    // ═══════════════════════════════════════
    //  View Functions
    // ═══════════════════════════════════════

    /// @notice Get position details
    function getPosition(
        address owner_,
        int24 tickLower,
        int24 tickUpper
    ) external view returns (
        uint128 _liquidity,
        uint256 _feeGrowthInside0LastX128,
        uint256 _feeGrowthInside1LastX128,
        uint128 _tokensOwed0,
        uint128 _tokensOwed1
    ) {
        bytes32 key = keccak256(abi.encodePacked(owner_, tickLower, tickUpper));
        Position storage pos = positions[key];
        return (
            pos.liquidity,
            pos.feeGrowthInside0LastX128,
            pos.feeGrowthInside1LastX128,
            pos.tokensOwed0,
            pos.tokensOwed1
        );
    }
}
