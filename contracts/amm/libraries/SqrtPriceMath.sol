// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SqrtPriceMath
 * @author Prakash Yadav
 * @notice Functions for computing swap amounts and next sqrt prices.
 *
 * ═══════════════════════════════════════════════════════
 * 📚 LEARNING: SWAP MATH EXPLAINED
 * ═══════════════════════════════════════════════════════
 *
 * When someone swaps tokens, we need to figure out:
 * 1. How many output tokens they get for their input
 * 2. What the new price will be after the swap
 *
 * The math uses sqrt prices because the formulas simplify beautifully:
 *
 * For a swap of token0 → token1 (buying token1):
 *   Δtoken0 = L * (1/√P_new - 1/√P_old)
 *   Δtoken1 = L * (√P_new - √P_old)
 *
 * Where:
 *   L = liquidity (how deep the pool is)
 *   √P = sqrt price
 *
 * The deeper the liquidity, the less the price moves for a given trade size.
 * This is called "price impact" — big trades in shallow pools move the price a lot.
 * ═══════════════════════════════════════════════════════
 */
library SqrtPriceMath {
    /**
     * @notice Gets the next sqrt price given a token0 input
     * @dev When swapping token0 for token1 (price goes DOWN):
     *      new_sqrtP = L * old_sqrtP / (L + amount * old_sqrtP)
     */
    function getNextSqrtPriceFromAmount0RoundingUp(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amount,
        bool add
    ) internal pure returns (uint160) {
        if (amount == 0) return sqrtPX96;

        uint256 numerator1 = uint256(liquidity) << 96;

        if (add) {
            unchecked {
                uint256 product = amount * sqrtPX96;
                if (product / amount == sqrtPX96) {
                    uint256 denominator = numerator1 + product;
                    if (denominator >= numerator1) {
                        return uint160(mulDivRoundingUp(numerator1, sqrtPX96, denominator));
                    }
                }
                return uint160(divRoundingUp(numerator1, (numerator1 / sqrtPX96) + amount));
            }
        } else {
            unchecked {
                uint256 product = amount * sqrtPX96;
                require(product / amount == sqrtPX96 && numerator1 > product);
                uint256 denominator = numerator1 - product;
                return uint160(mulDivRoundingUp(numerator1, sqrtPX96, denominator));
            }
        }
    }

    /**
     * @notice Gets the next sqrt price given a token1 input
     * @dev When swapping token1 for token0 (price goes UP):
     *      new_sqrtP = old_sqrtP + amount / L
     */
    function getNextSqrtPriceFromAmount1RoundingDown(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amount,
        bool add
    ) internal pure returns (uint160) {
        if (add) {
            uint256 quotient = (amount << 96) / liquidity;
            return uint160(uint256(sqrtPX96) + quotient);
        } else {
            uint256 quotient = divRoundingUp(amount << 96, liquidity);
            require(sqrtPX96 > quotient);
            return uint160(uint256(sqrtPX96) - quotient);
        }
    }

    /**
     * @notice Gets the amount of token0 delta between two sqrt prices
     * @dev amount0 = liquidity * (1/sqrtP_lower - 1/sqrtP_upper)
     */
    function getAmount0Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount0) {
        unchecked {
            if (sqrtRatioAX96 > sqrtRatioBX96) {
                (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
            }

            uint256 numerator1 = uint256(liquidity) << 96;
            uint256 numerator2 = sqrtRatioBX96 - sqrtRatioAX96;

            require(sqrtRatioAX96 > 0);

            if (roundUp) {
                amount0 = divRoundingUp(
                    mulDivRoundingUp(numerator1, numerator2, sqrtRatioBX96),
                    sqrtRatioAX96
                );
            } else {
                amount0 = (numerator1 * numerator2 / sqrtRatioBX96) / sqrtRatioAX96;
            }
        }
    }

    /**
     * @notice Gets the amount of token1 delta between two sqrt prices
     * @dev amount1 = liquidity * (sqrtP_upper - sqrtP_lower)
     */
    function getAmount1Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount1) {
        unchecked {
            if (sqrtRatioAX96 > sqrtRatioBX96) {
                (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
            }

            if (roundUp) {
                amount1 = mulDivRoundingUp(liquidity, sqrtRatioBX96 - sqrtRatioAX96, 1 << 96);
            } else {
                amount1 = uint256(liquidity) * (sqrtRatioBX96 - sqrtRatioAX96) / (1 << 96);
            }
        }
    }

    // ═══════════════════════════════════════
    //  Internal Math Helpers
    // ═══════════════════════════════════════

    function mulDivRoundingUp(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            result = (a * b) / denominator;
            if (mulmod(a, b, denominator) > 0) {
                require(result < type(uint256).max);
                result++;
            }
        }
    }

    function divRoundingUp(uint256 x, uint256 d) internal pure returns (uint256 z) {
        unchecked {
            z = x / d;
            if (x % d > 0) z++;
        }
    }
}
