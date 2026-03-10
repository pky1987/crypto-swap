// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ICryptoSwapFactory
 * @notice Interface for the factory contract that creates new trading pools.
 *
 * WHAT IS A FACTORY?
 * - A factory is a contract that creates other contracts (pools)
 * - For each token pair (e.g., ETH/USDC) and fee tier (e.g., 0.3%),
 *   the factory creates a unique Pool contract
 * - This is the "Factory Pattern" from software design
 *
 * WHY USE A FACTORY?
 * - Standardizes pool creation
 * - Prevents duplicate pools for the same pair
 * - Makes it easy to find pools (factory keeps a registry)
 */
interface ICryptoSwapFactory {
    /// @notice Emitted when a new pool is created
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        uint24 indexed fee,
        address pool
    );

    /// @notice Creates a new trading pool for a token pair
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @param fee Fee tier in hundredths of a bip (e.g., 3000 = 0.30%)
    /// @return pool The address of the newly created pool
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool);

    /// @notice Gets the pool address for a given pair and fee
    /// @return pool The pool address (address(0) if it doesn't exist)
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);

    /// @notice Returns all pool addresses created by this factory
    function allPools(uint256 index) external view returns (address);

    /// @notice Returns total number of pools created
    function allPoolsLength() external view returns (uint256);

    /// @notice Returns the protocol fee collector address
    function feeCollector() external view returns (address);
}
