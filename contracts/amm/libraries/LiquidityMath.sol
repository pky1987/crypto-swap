// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title LiquidityMath
 * @notice Functions for safely adding and subtracting liquidity.
 *
 * 📚 LEARNING: WHAT IS LIQUIDITY?
 *
 * Liquidity (L) measures how "deep" a pool is:
 * - High liquidity = small price changes per trade (good for traders)
 * - Low liquidity  = large price changes per trade (bad for traders, "high slippage")
 *
 * FORMULA: L = sqrt(x * y)
 * Where x and y are the token reserves.
 *
 * In concentrated liquidity (V3 style):
 * - LPs choose a price range [P_low, P_high]
 * - Their liquidity only works within that range
 * - This makes the capital more efficient (up to 4000x!)
 *
 * EXAMPLE:
 *   Full range LP: $10,000 spread across ALL prices ($0 → $∞)
 *   Concentrated LP: $10,000 focused on ETH price $2,800-$3,200
 *   The concentrated LP earns WAY more fees because their capital
 *   is concentrated where most trades happen.
 */
library LiquidityMath {
    /**
     * @notice Add a signed liquidity delta to liquidity.
     * @dev Reverts on overflow or underflow.
     * @param x The current liquidity
     * @param y The delta to add (can be negative for removes)
     * @return z The resulting liquidity
     */
    function addDelta(uint128 x, int128 y) internal pure returns (uint128 z) {
        if (y < 0) {
            require((z = x - uint128(-y)) < x, "LS");
        } else {
            require((z = x + uint128(y)) >= x, "LA");
        }
    }
}
