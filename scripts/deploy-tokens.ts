import { ethers } from "hardhat";

/**
 * 📚 DEPLOYMENT SCRIPT: Mock Tokens
 *
 * This deploys test tokens for development:
 * - WETH (Wrapped Ether)
 * - USDC (USD Coin mock)
 * - DAI (Dai mock)
 * - WBTC (Wrapped Bitcoin mock)
 *
 * WHAT YOU'LL LEARN:
 * - How to deploy contracts with Hardhat
 * - How to interact with deployed contracts
 * - How a "deployer" wallet works
 *
 * RUN: npx hardhat run scripts/deploy-tokens.ts --network localhost
 */
async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("═══════════════════════════════════════════════════");
  console.log("🪙 Deploying Mock Tokens");
  console.log("═══════════════════════════════════════════════════");
  console.log(`Deployer: ${deployer.address}`);
  console.log(`Balance:  ${ethers.formatEther(await ethers.provider.getBalance(deployer.address))} ETH`);
  console.log("");

  // ---- Deploy WETH ----
  console.log("📦 Deploying WETH...");
  const WETH = await ethers.getContractFactory("WETH9");
  const weth = await WETH.deploy();
  await weth.waitForDeployment();
  const wethAddress = await weth.getAddress();
  console.log(`   ✅ WETH deployed to: ${wethAddress}`);

  // ---- Deploy USDC (6 decimals, like real USDC) ----
  console.log("📦 Deploying USDC...");
  const MockERC20 = await ethers.getContractFactory("MockERC20");
  const usdc = await MockERC20.deploy("USD Coin", "USDC", 6);
  await usdc.waitForDeployment();
  const usdcAddress = await usdc.getAddress();
  console.log(`   ✅ USDC deployed to: ${usdcAddress}`);

  // ---- Deploy DAI (18 decimals) ----
  console.log("📦 Deploying DAI...");
  const dai = await MockERC20.deploy("Dai Stablecoin", "DAI", 18);
  await dai.waitForDeployment();
  const daiAddress = await dai.getAddress();
  console.log(`   ✅ DAI deployed to: ${daiAddress}`);

  // ---- Deploy WBTC (8 decimals, like real WBTC) ----
  console.log("📦 Deploying WBTC...");
  const wbtc = await MockERC20.deploy("Wrapped Bitcoin", "WBTC", 8);
  await wbtc.waitForDeployment();
  const wbtcAddress = await wbtc.getAddress();
  console.log(`   ✅ WBTC deployed to: ${wbtcAddress}`);

  // ---- Mint initial supplies ----
  console.log("\n🏭 Minting initial token supplies...");

  // Mint 1,000,000 USDC to deployer (6 decimals → 1e12)
  const usdcMintAmount = ethers.parseUnits("1000000", 6);
  await usdc.mint(deployer.address, usdcMintAmount);
  console.log(`   ✅ Minted 1,000,000 USDC to deployer`);

  // Mint 1,000,000 DAI (18 decimals)
  const daiMintAmount = ethers.parseEther("1000000");
  await dai.mint(deployer.address, daiMintAmount);
  console.log(`   ✅ Minted 1,000,000 DAI to deployer`);

  // Mint 100 WBTC (8 decimals)
  const wbtcMintAmount = ethers.parseUnits("100", 8);
  await wbtc.mint(deployer.address, wbtcMintAmount);
  console.log(`   ✅ Minted 100 WBTC to deployer`);

  // Wrap some ETH into WETH
  await weth.deposit({ value: ethers.parseEther("100") });
  console.log(`   ✅ Wrapped 100 ETH into WETH`);

  // ---- Summary ----
  console.log("\n═══════════════════════════════════════════════════");
  console.log("📋 DEPLOYMENT SUMMARY");
  console.log("═══════════════════════════════════════════════════");
  console.log(`WETH:  ${wethAddress}`);
  console.log(`USDC:  ${usdcAddress}`);
  console.log(`DAI:   ${daiAddress}`);
  console.log(`WBTC:  ${wbtcAddress}`);
  console.log("═══════════════════════════════════════════════════");
  console.log("\n💡 Save these addresses! You'll need them for the AMM deployment.\n");

  // Return addresses for use by other scripts
  return { weth: wethAddress, usdc: usdcAddress, dai: daiAddress, wbtc: wbtcAddress };
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
