import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

/**
 * 📚 TEST HELPERS
 *
 * Utility functions used across all test files.
 * These abstract common operations like:
 * - Deploying contracts
 * - Minting tokens
 * - Calculating prices
 */

/**
 * Deploy a MockERC20 token with the given parameters.
 */
export async function deployMockToken(
  name: string,
  symbol: string,
  decimals: number,
  signer?: Signer
) {
  const Factory = await ethers.getContractFactory("MockERC20", signer);
  const token = await Factory.deploy(name, symbol, decimals);
  await token.waitForDeployment();
  return token;
}

/**
 * Deploy the WETH9 contract.
 */
export async function deployWETH(signer?: Signer) {
  const Factory = await ethers.getContractFactory("WETH9", signer);
  const weth = await Factory.deploy();
  await weth.waitForDeployment();
  return weth;
}

/**
 * Deploy the full AMM stack: Factory + Router.
 */
export async function deployAMM(wethAddress: string, signer?: Signer) {
  const FactoryFactory = await ethers.getContractFactory("CryptoSwapFactory", signer);
  const factory = await FactoryFactory.deploy();
  await factory.waitForDeployment();

  const RouterFactory = await ethers.getContractFactory("CryptoSwapRouter", signer);
  const router = await RouterFactory.deploy(await factory.getAddress(), wethAddress);
  await router.waitForDeployment();

  return { factory, router };
}

/**
 * Calculate sqrtPriceX96 from a human-readable price.
 *
 * @param price The price of token0 in terms of token1
 *              (e.g., 3000 means 1 token0 = 3000 token1)
 * @param decimals0 Decimals of token0
 * @param decimals1 Decimals of token1
 * @returns sqrtPriceX96 as bigint
 *
 * 📚 FORMULA:
 *   adjustedPrice = price * 10^decimals1 / 10^decimals0
 *   sqrtPriceX96 = sqrt(adjustedPrice) * 2^96
 */
export function encodePriceSqrt(
  price: number,
  decimals0: number = 18,
  decimals1: number = 18
): bigint {
  const adjustedPrice = price * (10 ** decimals1) / (10 ** decimals0);
  const sqrtPrice = Math.sqrt(adjustedPrice);
  return BigInt(Math.floor(sqrtPrice * (2 ** 96)));
}

/**
 * Get the current block timestamp + offset.
 */
export async function getDeadline(offsetSeconds: number = 600): Promise<number> {
  const block = await ethers.provider.getBlock("latest");
  return (block?.timestamp || Math.floor(Date.now() / 1000)) + offsetSeconds;
}

/**
 * Format a token amount for display.
 */
export function formatTokenAmount(
  amount: bigint,
  decimals: number,
  symbol: string
): string {
  return `${ethers.formatUnits(amount, decimals)} ${symbol}`;
}
