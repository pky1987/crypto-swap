// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/ICryptoSwapFactory.sol";
import "../interfaces/ICryptoSwapPool.sol";
import "./CryptoSwapPool.sol";
import "./libraries/TickMath.sol";

/**
 * @title CryptoSwapRouter
 * @notice User-facing contract for swaps and liquidity operations.
 *
 * ═══════════════════════════════════════════════════════
 * 📚 LEARNING: WHY DO WE NEED A ROUTER?
 * ═══════════════════════════════════════════════════════
 *
 * Users DON'T interact with pools directly. Instead, they use the Router:
 *
 * 1. SAFETY: The router adds slippage protection and deadline checks
 * 2. CONVENIENCE: It handles token approvals and transfers
 * 3. MULTI-HOP: It can route through multiple pools (e.g., ETH→USDC→DAI)
 * 4. WETH: It wraps/unwraps ETH automatically
 *
 * FLOW:
 *   User → Router → Pool(s) → User gets output tokens
 *
 * The Router implements the callback interfaces, so when the Pool
 * asks for input tokens, the Router transfers them from the user.
 * ═══════════════════════════════════════════════════════
 */
contract CryptoSwapRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════
    //  State
    // ═══════════════════════════════════════

    /// @notice The factory contract (to look up pools)
    ICryptoSwapFactory public immutable factory;

    /// @notice WETH address (for ETH wrapping)
    address public immutable WETH;

    // ═══════════════════════════════════════
    //  Structs
    // ═══════════════════════════════════════

    /**
     * @notice Parameters for a single-pool swap.
     *
     * 📚 CONCEPTS:
     * - tokenIn: The token you're giving
     * - tokenOut: The token you want
     * - fee: Which pool to use (different fee tiers have different pools)
     * - amountIn: How much you're giving
     * - amountOutMinimum: SLIPPAGE PROTECTION — the minimum you'll accept
     *   → If the output would be less, the transaction REVERTS
     *   → This protects against "sandwich attacks" (MEV)
     * - sqrtPriceLimitX96: Price limit — prevents excessive price impact
     * - deadline: Transaction must execute before this timestamp
     *   → Protects against your transaction sitting in the mempool too long
     */
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    struct AddLiquidityParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 amount;
        address recipient;
        uint256 deadline;
    }

    // ═══════════════════════════════════════
    //  Events
    // ═══════════════════════════════════════

    event SwapExecuted(
        address indexed sender,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address pool
    );

    event LiquidityAdded(
        address indexed provider,
        address indexed pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    // ═══════════════════════════════════════
    //  Modifiers
    // ═══════════════════════════════════════

    /**
     * @dev Ensures the transaction hasn't expired.
     * Users set a deadline when submitting; if the tx takes too long
     * to be mined, it reverts instead of executing at a stale price.
     */
    modifier checkDeadline(uint256 deadline) {
        require(block.timestamp <= deadline, "EXPIRED");
        _;
    }

    // ═══════════════════════════════════════
    //  Constructor
    // ═══════════════════════════════════════

    constructor(address _factory, address _weth) {
        factory = ICryptoSwapFactory(_factory);
        WETH = _weth;
    }

    // ═══════════════════════════════════════
    //  Swap Functions
    // ═══════════════════════════════════════

    /**
     * @notice Swap an exact amount of input tokens for as many output tokens as possible.
     *
     * 📚 THIS IS THE MOST COMMON SWAP TYPE:
     * "I want to swap exactly 1 ETH. Give me as much USDC as I can get."
     *
     * EXAMPLE:
     *   exactInputSingle({
     *     tokenIn: WETH,
     *     tokenOut: USDC,
     *     fee: 3000,           // 0.30% fee tier
     *     recipient: myAddress,
     *     deadline: block.timestamp + 600,  // 10 minutes
     *     amountIn: 1 ether,
     *     amountOutMinimum: 2700 * 1e6,     // Minimum 2700 USDC (slippage protection)
     *     sqrtPriceLimitX96: 0              // No price limit
     *   })
     */
    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external nonReentrant checkDeadline(params.deadline) returns (uint256 amountOut) {
        // Find the pool
        address pool = factory.getPool(params.tokenIn, params.tokenOut, params.fee);
        require(pool != address(0), "POOL_NOT_FOUND");

        // Determine swap direction
        bool zeroForOne = params.tokenIn < params.tokenOut;

        // Transfer input tokens from user to this contract
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);

        // Approve pool to spend our tokens
        IERC20(params.tokenIn).approve(pool, params.amountIn);

        // Set price limit
        uint160 sqrtPriceLimitX96 = params.sqrtPriceLimitX96 == 0
            ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
            : params.sqrtPriceLimitX96;

        // Execute swap
        (int256 amount0, int256 amount1) = CryptoSwapPool(pool).swap(
            params.recipient,
            zeroForOne,
            int256(params.amountIn),
            sqrtPriceLimitX96,
            abi.encode(msg.sender) // data for callback
        );

        // Calculate output
        amountOut = uint256(-(zeroForOne ? amount1 : amount0));

        // 🛡️ SLIPPAGE CHECK: Revert if output is too low
        require(amountOut >= params.amountOutMinimum, "TOO_LITTLE_RECEIVED");

        emit SwapExecuted(
            msg.sender,
            params.tokenIn,
            params.tokenOut,
            params.amountIn,
            amountOut,
            pool
        );
    }

    /**
     * @notice Swap for an exact amount of output tokens, paying at most a specified amount of input.
     *
     * 📚 REVERSE SWAP:
     * "I want exactly 3000 USDC. I'll pay up to 1.1 ETH for it."
     */
    function exactOutputSingle(
        ExactOutputSingleParams calldata params
    ) external nonReentrant checkDeadline(params.deadline) returns (uint256 amountIn) {
        address pool = factory.getPool(params.tokenIn, params.tokenOut, params.fee);
        require(pool != address(0), "POOL_NOT_FOUND");

        bool zeroForOne = params.tokenIn < params.tokenOut;

        // Transfer maximum input from user
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountInMaximum);
        IERC20(params.tokenIn).approve(pool, params.amountInMaximum);

        uint160 sqrtPriceLimitX96 = params.sqrtPriceLimitX96 == 0
            ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
            : params.sqrtPriceLimitX96;

        (int256 amount0, int256 amount1) = CryptoSwapPool(pool).swap(
            params.recipient,
            zeroForOne,
            -int256(params.amountOut),
            sqrtPriceLimitX96,
            abi.encode(msg.sender)
        );

        amountIn = uint256(zeroForOne ? amount0 : amount1);

        // 🛡️ SLIPPAGE CHECK: Revert if input cost is too high
        require(amountIn <= params.amountInMaximum, "TOO_MUCH_REQUESTED");

        // Refund excess tokens
        if (amountIn < params.amountInMaximum) {
            IERC20(params.tokenIn).safeTransfer(msg.sender, params.amountInMaximum - amountIn);
        }

        emit SwapExecuted(
            msg.sender,
            params.tokenIn,
            params.tokenOut,
            amountIn,
            params.amountOut,
            pool
        );
    }

    // ═══════════════════════════════════════
    //  Liquidity Functions
    // ═══════════════════════════════════════

    /**
     * @notice Add liquidity to a pool within a price range.
     *
     * 📚 CONCENTRATED LIQUIDITY IN ACTION:
     * Instead of providing liquidity across ALL prices,
     * you choose a range (tickLower, tickUpper).
     *
     * EXAMPLE:
     *   ETH is trading at $3,000
     *   You think it'll stay between $2,800–$3,200
     *   You provide liquidity in that range
     *   → You earn fees from ALL trades in that range
     *   → Your capital is much more efficient than full-range
     */
    function addLiquidity(
        AddLiquidityParams calldata params
    ) external nonReentrant checkDeadline(params.deadline) returns (
        uint256 amount0,
        uint256 amount1
    ) {
        address pool = factory.getPool(params.token0, params.token1, params.fee);
        require(pool != address(0), "POOL_NOT_FOUND");

        // Calculate how many tokens we need for this liquidity amount
        // The pool will callback to us for the tokens
        IERC20(params.token0).approve(pool, type(uint256).max);
        IERC20(params.token1).approve(pool, type(uint256).max);

        (amount0, amount1) = CryptoSwapPool(pool).mint(
            params.recipient,
            params.tickLower,
            params.tickUpper,
            params.amount,
            abi.encode(msg.sender)
        );

        emit LiquidityAdded(
            msg.sender,
            pool,
            params.tickLower,
            params.tickUpper,
            params.amount,
            amount0,
            amount1
        );
    }

    // ═══════════════════════════════════════
    //  Callbacks (called by Pool)
    // ═══════════════════════════════════════

    /**
     * @notice Called by the pool during a swap to collect input tokens.
     * @dev The pool sends output tokens first, then calls this to get input.
     */
    function cryptoSwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        require(amount0Delta > 0 || amount1Delta > 0, "CALLBACK");

        // Decode the original sender from callback data
        address sender = abi.decode(data, (address));

        // Transfer the required tokens to the pool
        if (amount0Delta > 0) {
            address _token0 = ICryptoSwapPool(msg.sender).token0();
            IERC20(_token0).safeTransferFrom(sender, msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            address _token1 = ICryptoSwapPool(msg.sender).token1();
            IERC20(_token1).safeTransferFrom(sender, msg.sender, uint256(amount1Delta));
        }
    }

    /**
     * @notice Called by the pool during a mint to collect tokens for liquidity.
     */
    function cryptoSwapMintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        address sender = abi.decode(data, (address));

        if (amount0Owed > 0) {
            address _token0 = ICryptoSwapPool(msg.sender).token0();
            IERC20(_token0).safeTransferFrom(sender, msg.sender, amount0Owed);
        }
        if (amount1Owed > 0) {
            address _token1 = ICryptoSwapPool(msg.sender).token1();
            IERC20(_token1).safeTransferFrom(sender, msg.sender, amount1Owed);
        }
    }

    // ═══════════════════════════════════════
    //  Helper / View Functions
    // ═══════════════════════════════════════

    /**
     * @notice Get a quote for a swap (how much output for a given input).
     * @dev This is a READ-ONLY function — doesn't execute the swap.
     *      Used by the frontend to show expected output before the user confirms.
     */
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 _fee,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        address pool = factory.getPool(tokenIn, tokenOut, _fee);
        require(pool != address(0), "POOL_NOT_FOUND");

        CryptoSwapPool poolContract = CryptoSwapPool(pool);
        uint128 poolLiquidity = poolContract.liquidity();
        uint160 currentSqrtPrice = poolContract.sqrtPriceX96();

        require(poolLiquidity > 0, "NO_LIQUIDITY");

        // Simple quote: use constant product approximation
        // In production, this would simulate the actual swap path
        bool zeroForOne = tokenIn < tokenOut;
        uint256 feeAmount = (amountIn * _fee) / 1000000;
        uint256 amountAfterFee = amountIn - feeAmount;

        if (zeroForOne) {
            uint160 nextSqrtPrice = SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(
                currentSqrtPrice, poolLiquidity, amountAfterFee, true
            );
            amountOut = SqrtPriceMath.getAmount1Delta(
                nextSqrtPrice, currentSqrtPrice, poolLiquidity, false
            );
        } else {
            uint160 nextSqrtPrice = SqrtPriceMath.getNextSqrtPriceFromAmount1RoundingDown(
                currentSqrtPrice, poolLiquidity, amountAfterFee, true
            );
            amountOut = SqrtPriceMath.getAmount0Delta(
                currentSqrtPrice, nextSqrtPrice, poolLiquidity, false
            );
        }
    }

    /// @notice Receive ETH (for WETH wrapping)
    receive() external payable {}
}
