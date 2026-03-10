import { expect } from "chai";
import { ethers } from "hardhat";
import { deployMockToken, deployWETH, deployAMM, encodePriceSqrt } from "../helpers/utils";

/**
 * 📚 FACTORY TESTS
 *
 * Tests for the CryptoSwapFactory contract.
 *
 * WHAT WE'RE TESTING:
 * 1. Can we create pools for token pairs?
 * 2. Does it prevent duplicate pools?
 * 3. Are fee tiers enforced?
 * 4. Do events fire correctly?
 *
 * HOW TO RUN:
 *   npx hardhat test test/amm/Factory.test.ts
 *
 * 📚 TESTING CONCEPTS:
 * - describe(): Groups related tests
 * - it(): A single test case
 * - expect(): Assertion (check if something is true)
 * - beforeEach(): Runs before each test (fresh state)
 */
describe("CryptoSwapFactory", function () {
  let factory: any;
  let router: any;
  let weth: any;
  let tokenA: any;
  let tokenB: any;
  let deployer: any;
  let user1: any;

  /**
   * beforeEach runs BEFORE every test.
   * This ensures each test starts with a fresh set of contracts.
   * (Tests should NOT depend on each other!)
   */
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
  //  Pool Creation Tests
  // ═══════════════════════════════════════

  describe("Pool Creation", function () {
    it("should create a pool for a valid token pair", async function () {
      const tokenAAddr = await tokenA.getAddress();
      const tokenBAddr = await tokenB.getAddress();

      // Create pool with 0.30% fee
      const tx = await factory.createPool(tokenAAddr, tokenBAddr, 3000);
      const receipt = await tx.wait();

      // Check pool was created
      const poolAddress = await factory.getPool(tokenAAddr, tokenBAddr, 3000);
      expect(poolAddress).to.not.equal(ethers.ZeroAddress);

      // Check pool count
      expect(await factory.allPoolsLength()).to.equal(1);
    });

    it("should sort tokens correctly (token0 < token1)", async function () {
      const tokenAAddr = await tokenA.getAddress();
      const tokenBAddr = await tokenB.getAddress();

      await factory.createPool(tokenAAddr, tokenBAddr, 3000);

      // Both directions should return the same pool
      const pool1 = await factory.getPool(tokenAAddr, tokenBAddr, 3000);
      const pool2 = await factory.getPool(tokenBAddr, tokenAAddr, 3000);
      expect(pool1).to.equal(pool2);
    });

    it("should emit PoolCreated event", async function () {
      const tokenAAddr = await tokenA.getAddress();
      const tokenBAddr = await tokenB.getAddress();

      // Determine sorted order
      const [token0, token1] = tokenAAddr.toLowerCase() < tokenBAddr.toLowerCase()
        ? [tokenAAddr, tokenBAddr]
        : [tokenBAddr, tokenAAddr];

      await expect(factory.createPool(tokenAAddr, tokenBAddr, 3000))
        .to.emit(factory, "PoolCreated")
        .withArgs(token0, token1, 3000, (poolAddr: string) => {
          // Pool address should be non-zero
          return poolAddr !== ethers.ZeroAddress;
        });
    });

    it("should support different fee tiers", async function () {
      const tokenAAddr = await tokenA.getAddress();
      const tokenBAddr = await tokenB.getAddress();

      // Create pools with different fee tiers
      await factory.createPool(tokenAAddr, tokenBAddr, 500);    // 0.05%
      await factory.createPool(tokenAAddr, tokenBAddr, 3000);   // 0.30%
      await factory.createPool(tokenAAddr, tokenBAddr, 10000);  // 1.00%

      // Each should be a different pool
      const pool1 = await factory.getPool(tokenAAddr, tokenBAddr, 500);
      const pool2 = await factory.getPool(tokenAAddr, tokenBAddr, 3000);
      const pool3 = await factory.getPool(tokenAAddr, tokenBAddr, 10000);

      expect(pool1).to.not.equal(pool2);
      expect(pool2).to.not.equal(pool3);
      expect(await factory.allPoolsLength()).to.equal(3);
    });
  });

  // ═══════════════════════════════════════
  //  Validation Tests
  // ═══════════════════════════════════════

  describe("Validation", function () {
    it("should revert when creating a pool with identical tokens", async function () {
      const tokenAAddr = await tokenA.getAddress();
      await expect(
        factory.createPool(tokenAAddr, tokenAAddr, 3000)
      ).to.be.revertedWith("IDENTICAL_ADDRESSES");
    });

    it("should revert when creating a pool with zero address", async function () {
      const tokenAAddr = await tokenA.getAddress();
      await expect(
        factory.createPool(tokenAAddr, ethers.ZeroAddress, 3000)
      ).to.be.revertedWith("ZERO_ADDRESS");
    });

    it("should revert when creating a duplicate pool", async function () {
      const tokenAAddr = await tokenA.getAddress();
      const tokenBAddr = await tokenB.getAddress();

      // Create pool
      await factory.createPool(tokenAAddr, tokenBAddr, 3000);

      // Try to create same pool again
      await expect(
        factory.createPool(tokenAAddr, tokenBAddr, 3000)
      ).to.be.revertedWith("POOL_EXISTS");
    });

    it("should revert with invalid fee tier", async function () {
      const tokenAAddr = await tokenA.getAddress();
      const tokenBAddr = await tokenB.getAddress();

      // Fee tier 999 is not enabled
      await expect(
        factory.createPool(tokenAAddr, tokenBAddr, 999)
      ).to.be.revertedWith("FEE_NOT_ENABLED");
    });
  });

  // ═══════════════════════════════════════
  //  Admin Tests
  // ═══════════════════════════════════════

  describe("Admin Functions", function () {
    it("should allow owner to change fee collector", async function () {
      await factory.setFeeCollector(user1.address);
      expect(await factory.feeCollector()).to.equal(user1.address);
    });

    it("should not allow non-owner to change fee collector", async function () {
      await expect(
        factory.connect(user1).setFeeCollector(user1.address)
      ).to.be.revertedWith("NOT_OWNER");
    });

    it("should allow owner to enable new fee tier", async function () {
      // Enable 0.01% fee with tick spacing 1
      await factory.enableFeeAmount(100, 1);
      expect(await factory.feeEnabled(100)).to.equal(true);
    });
  });
});
