// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ICryptoSwapPool
 * @notice Interface for individual trading pool contracts.
 *
 * WHAT IS A POOL?
 * - A pool holds reserves of two tokens (e.g., 100 ETH + 300,000 USDC)
 * - It uses a mathematical formula to determine swap prices
 * - Anyone can swap tokens through the pool
 * - Anyone can provide liquidity to earn fees
 *
 * THE CONSTANT PRODUCT FORMULA: x * y = k
 * - x = reserve of token0
 * - y = reserve of token1
 * - k = constant (product of reserves)
 * - When you swap, one reserve goes up, the other goes down, keeping k constant
 *
 * EXAMPLE:
 *   Pool has: 10 ETH ($3000 each) + 30,000 USDC
 *   k = 10 * 30,000 = 300,000
 *
 *   You want to buy 1 ETH:
 *   New ETH reserve = 9
 *   New USDC reserve = 300,000 / 9 = 33,333.33
 *   Cost = 33,333.33 - 30,000 = 3,333.33 USDC (higher than spot due to "price impact")
 */
interface ICryptoSwapPool {
    /// @notice Emitted on every swap
    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

    /// @notice Emitted when liquidity is added
    event Mint(
        address sender,
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when liquidity is removed
    event Burn(
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Initialize the pool with a starting price
    /// @param sqrtPriceX96 The initial sqrt price as a Q64.96 value
    function initialize(uint160 sqrtPriceX96) external;

    /// @notice Swap tokens
    /// @param recipient Address to receive output tokens
    /// @param zeroForOne True if swapping token0 for token1
    /// @param amountSpecified Positive = exact input, negative = exact output
    /// @param sqrtPriceLimitX96 Price limit for the swap
    /// @param data Callback data
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);

    /// @notice Add liquidity to a position
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Remove liquidity from a position
    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Collect earned fees
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);

    // ---- View Functions ----

    /// @notice The first token in the pair (sorted by address)
    function token0() external view returns (address);

    /// @notice The second token in the pair
    function token1() external view returns (address);

    /// @notice The fee tier for this pool
    function fee() external view returns (uint24);

    /// @notice The current sqrt price
    function sqrtPriceX96() external view returns (uint160);

    /// @notice The current tick
    function tick() external view returns (int24);

    /// @notice The current liquidity
    function liquidity() external view returns (uint128);
}
