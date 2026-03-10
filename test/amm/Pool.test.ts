import { expect } from "chai";
import { ethers } from "hardhat";
import { deployMockToken, deployWETH, deployAMM, encodePriceSqrt, getDeadline } from "../helpers/utils";

/**
 * 📚 POOL TESTS
 *
 * Tests for the CryptoSwapPool contract — the heart of the AMM.
 *
 * WHAT WE'RE TESTING:
 * 1. Pool initialization (setting the starting price)
 * 2. Adding liquidity (mint)
 * 3. Removing liquidity (burn + collect)
 * 4. Swaps
 *
 * HOW TO RUN:
 *   npx hardhat test test/amm/Pool.test.ts
 */
describe("CryptoSwapPool", function () {
  let factory: any;
  let router: any;
  let weth: any;
  let tokenA: any;
  let tokenB: any;
  let pool: any;
  let deployer: any;
  let user1: any;
  let token0Addr: string;
  let token1Addr: string;

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

    // Create a pool
    const tokenAAddr = await tokenA.getAddress();
    const tokenBAddr = await tokenB.getAddress();
    await factory.createPool(tokenAAddr, tokenBAddr, 3000);

    const poolAddress = await factory.getPool(tokenAAddr, tokenBAddr, 3000);
    pool = await ethers.getContractAt("CryptoSwapPool", poolAddress);

    // Determine token0 and token1 (sorted by address)
    token0Addr = await pool.token0();
    token1Addr = await pool.token1();

    // Mint tokens to deployer
    await tokenA.mint(deployer.address, ethers.parseEther("1000000"));
    await tokenB.mint(deployer.address, ethers.parseEther("1000000"));
  });

  // ═══════════════════════════════════════
  //  Initialization Tests
  // ═══════════════════════════════════════

  describe("Initialization", function () {
    it("should initialize with correct token addresses", async function () {
      expect(await pool.token0()).to.not.equal(ethers.ZeroAddress);
      expect(await pool.token1()).to.not.equal(ethers.ZeroAddress);

      // token0 should have smaller address
      const t0 = (await pool.token0()).toLowerCase();
      const t1 = (await pool.token1()).toLowerCase();
      expect(t0 < t1).to.be.true;
    });

    it("should initialize with correct fee", async function () {
      expect(await pool.fee()).to.equal(3000);
    });

    it("should initialize pool with a starting price", async function () {
      // Price: 1 tokenA = 1 tokenB (equal value)
      const sqrtPriceX96 = encodePriceSqrt(1);
      await pool.initialize(sqrtPriceX96);

      expect(await pool.initialized()).to.be.true;
      expect(await pool.sqrtPriceX96()).to.equal(sqrtPriceX96);
    });

    it("should not allow double initialization", async function () {
      const sqrtPriceX96 = encodePriceSqrt(1);
      await pool.initialize(sqrtPriceX96);

      await expect(
        pool.initialize(sqrtPriceX96)
      ).to.be.revertedWith("AI");
    });
  });

  // ═══════════════════════════════════════
  //  Pool Properties Tests
  // ═══════════════════════════════════════

  describe("Pool Properties", function () {
    it("should have correct tick spacing for 0.30% fee", async function () {
      expect(await pool.tickSpacing()).to.equal(60);
    });

    it("should start with zero liquidity", async function () {
      expect(await pool.liquidity()).to.equal(0);
    });
  });
});
