import { ethers } from "hardhat";

/**
 * 📚 DEPLOYMENT SCRIPT: AMM Contracts
 *
 * Deploys:
 * 1. CryptoSwapFactory — creates new pools
 * 2. CryptoSwapRouter — user-facing swap/liquidity interface
 * 3. A sample pool (ETH/USDC) — for immediate testing
 *
 * PREREQUISITES:
 * - Run deploy-tokens.ts first to get token addresses
 * - Update the token addresses below
 *
 * RUN: npx hardhat run scripts/deploy-amm.ts --network localhost
 */

// ⚠️ UPDATE THESE after running deploy-tokens.ts
const TOKEN_ADDRESSES = {
  WETH: "", // Will be set from command line or hardcoded after deploy-tokens
  USDC: "",
};

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("═══════════════════════════════════════════════════");
  console.log("🔄 Deploying CryptoSwap AMM");
  console.log("═══════════════════════════════════════════════════");
  console.log(`Deployer: ${deployer.address}`);
  console.log(`Balance:  ${ethers.formatEther(await ethers.provider.getBalance(deployer.address))} ETH`);
  console.log("");

  // ---- Step 1: Deploy Mock Tokens (if not already deployed) ----
  let wethAddress = TOKEN_ADDRESSES.WETH;
  let usdcAddress = TOKEN_ADDRESSES.USDC;

  if (!wethAddress || !usdcAddress) {
    console.log("📦 Deploying mock tokens first...\n");

    const WETH = await ethers.getContractFactory("WETH9");
    const weth = await WETH.deploy();
    await weth.waitForDeployment();
    wethAddress = await weth.getAddress();
    console.log(`   ✅ WETH: ${wethAddress}`);

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const usdc = await MockERC20.deploy("USD Coin", "USDC", 6);
    await usdc.waitForDeployment();
    usdcAddress = await usdc.getAddress();
    console.log(`   ✅ USDC: ${usdcAddress}`);

    // Mint tokens
    await usdc.mint(deployer.address, ethers.parseUnits("1000000", 6));
    await weth.deposit({ value: ethers.parseEther("100") });
    console.log("   ✅ Minted 1,000,000 USDC and wrapped 100 ETH\n");
  }

  // ---- Step 2: Deploy Factory ----
  console.log("📦 Deploying CryptoSwapFactory...");
  const Factory = await ethers.getContractFactory("CryptoSwapFactory");
  const factory = await Factory.deploy();
  await factory.waitForDeployment();
  const factoryAddress = await factory.getAddress();
  console.log(`   ✅ Factory deployed to: ${factoryAddress}`);

  // ---- Step 3: Deploy Router ----
  console.log("📦 Deploying CryptoSwapRouter...");
  const Router = await ethers.getContractFactory("CryptoSwapRouter");
  const router = await Router.deploy(factoryAddress, wethAddress);
  await router.waitForDeployment();
  const routerAddress = await router.getAddress();
  console.log(`   ✅ Router deployed to: ${routerAddress}`);

  // ---- Step 4: Create a sample ETH/USDC pool ----
  console.log("\n📦 Creating ETH/USDC pool (0.30% fee)...");
  const tx = await factory.createPool(wethAddress, usdcAddress, 3000);
  const receipt = await tx.wait();

  // Get pool address from event
  const poolCreatedEvent = receipt?.logs?.find((log: any) => {
    try {
      return factory.interface.parseLog({ topics: log.topics as string[], data: log.data })?.name === "PoolCreated";
    } catch { return false; }
  });

  let poolAddress: string;
  if (poolCreatedEvent) {
    const parsed = factory.interface.parseLog({
      topics: poolCreatedEvent.topics as string[],
      data: poolCreatedEvent.data,
    });
    poolAddress = parsed?.args?.pool;
  } else {
    poolAddress = await factory.getPool(wethAddress, usdcAddress, 3000);
  }
  console.log(`   ✅ ETH/USDC Pool: ${poolAddress}`);

  // ---- Step 5: Initialize the pool with a price ----
  console.log("\n📦 Initializing pool with price: 1 ETH = 3000 USDC...");

  /**
   * 📚 CALCULATING sqrtPriceX96:
   *
   * price = token1/token0 = 3000 USDC per ETH
   * BUT: we need to account for decimal differences!
   *   ETH has 18 decimals, USDC has 6 decimals
   *   Actual price ratio = 3000 * 10^6 / 10^18 = 3000 * 10^(-12)
   *
   * sqrtPriceX96 = sqrt(price) * 2^96
   *
   * For simplicity, we use a pre-calculated value.
   * In production, you'd use a helper function.
   */
  const pool = await ethers.getContractAt("CryptoSwapPool", poolAddress);

  // Calculate sqrtPriceX96 for 1 ETH = 3000 USDC
  // sqrtPriceX96 = sqrt(3000 * 10^6 / 10^18) * 2^96
  // = sqrt(3 * 10^-9) * 2^96
  // ≈ 4339048060990336 (approximate)
  const sqrtPriceX96 = BigInt("4339048060990336") * BigInt(2 ** 32);

  await pool.initialize(sqrtPriceX96);
  console.log(`   ✅ Pool initialized!`);

  // ---- Summary ----
  console.log("\n═══════════════════════════════════════════════════");
  console.log("📋 AMM DEPLOYMENT SUMMARY");
  console.log("═══════════════════════════════════════════════════");
  console.log(`Factory:       ${factoryAddress}`);
  console.log(`Router:        ${routerAddress}`);
  console.log(`ETH/USDC Pool: ${poolAddress}`);
  console.log(`WETH:          ${wethAddress}`);
  console.log(`USDC:          ${usdcAddress}`);
  console.log("═══════════════════════════════════════════════════");
  console.log("\n🎉 AMM is ready! You can now:");
  console.log("   1. Add liquidity to the ETH/USDC pool");
  console.log("   2. Execute swaps through the router");
  console.log("   3. Run tests: npx hardhat test");
  console.log("");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
