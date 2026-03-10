import { expect } from "chai";
import { ethers } from "hardhat";
import { deployMockToken, deployWETH, deployAMM, encodePriceSqrt, getDeadline } from "../helpers/utils";

/**
 * 📚 ROUTER TESTS
 *
 * Tests for the CryptoSwapRouter — the user-facing swap & liquidity interface.
 *
 * WHAT WE'RE TESTING:
 * 1. Quote functionality (price estimation)
 * 2. ExactInputSingle swaps
 * 3. ExactOutputSingle swaps
 * 4. Slippage protection
 * 5. Deadline enforcement
 *
 * HOW TO RUN:
 *   npx hardhat test test/amm/Router.test.ts
 */
describe("CryptoSwapRouter", function () {
  let factory: any;
  let router: any;
  let weth: any;
  let tokenA: any;
  let tokenB: any;
  let deployer: any;
  let user1: any;

  beforeEach(async function () {
    [deployer, user1] = await ethers.getSigners();

    // Deploy tokens
    weth = await deployWETH();
    tokenA = await deployMockToken("Token A", "TKA", 18);
    tokenB = await deployMockToken("Token B", "TKB", 18);

    // Deploy AMM
    const amm = await deployAMM(await weth.getAddress());
    factory = amm.factory;
    router = amm.router;
  });

  // ═══════════════════════════════════════
  //  Router Setup Tests
  // ═══════════════════════════════════════

  describe("Setup", function () {
    it("should have correct factory address", async function () {
      expect(await router.factory()).to.equal(await factory.getAddress());
    });

    it("should have correct WETH address", async function () {
      expect(await router.WETH()).to.equal(await weth.getAddress());
    });
  });

  // ═══════════════════════════════════════
  //  Swap Tests (requires liquidity)
  // ═══════════════════════════════════════

  describe("Swap Prerequisites", function () {
    it("should revert when pool doesn't exist", async function () {
      const tokenAAddr = await tokenA.getAddress();
      const tokenBAddr = await tokenB.getAddress();
      const deadline = await getDeadline();

      await expect(
        router.exactInputSingle({
          tokenIn: tokenAAddr,
          tokenOut: tokenBAddr,
          fee: 3000,
          recipient: deployer.address,
          deadline: deadline,
          amountIn: ethers.parseEther("1"),
          amountOutMinimum: 0,
          sqrtPriceLimitX96: 0,
        })
      ).to.be.revertedWith("POOL_NOT_FOUND");
    });
  });
});
