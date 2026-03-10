import { ethers } from "hardhat";
import crypto from "crypto";
import * as dotenv from "dotenv";

dotenv.config();

/**
 * 🔐 DECRYPTION HELPER
 * Modern PBKDF2 key/IV derivation for AES-256-CBC
 */
function deriveKeyIv(password: string, salt: Buffer, keyLen: number, ivLen: number) {
  const keyIv = crypto.pbkdf2Sync(password, salt, 10000, keyLen + ivLen, "sha256");
  return {
    key: keyIv.slice(0, keyLen),
    iv: keyIv.slice(keyLen, keyLen + ivLen)
  };
}

/**
 * Decrypts the private key using the provided password
 */
function decryptPrivateKey(encryptedKey: string, password: string): string {
  try {
    const data = Buffer.from(encryptedKey, "base64");
    // OpenSSL format usually starts with "Salted__" (8 bytes) followed by 8 bytes of salt
    const salt = data.slice(8, 16);
    const ciphertext = data.slice(16);

    const { key, iv } = deriveKeyIv(password, salt, 32, 16);
    const decipher = crypto.createDecipheriv("aes-256-cbc", key, iv);

    let decrypted = decipher.update(ciphertext as any, "binary", "utf8");
    decrypted += decipher.final("utf8");

    return decrypted.trim();
  } catch (error: any) {
    throw new Error(`Decryption failed: ${error.message}`);
  }
}

async function main() {
  // 1. Decrypt Private Key
  const encryptedKey = process.env.PRIVATE_KEY;
  const password = process.env.ENCRYPTION_PASSWORD;

  if (!encryptedKey || !password) {
    console.error("❌ Error: PRIVATE_KEY or ENCRYPTION_PASSWORD missing in .env");
    process.exit(1);
  }

  let privateKey: string;
  try {
    privateKey = decryptPrivateKey(encryptedKey, password);
    if (!privateKey.startsWith("0x")) {
      privateKey = "0x" + privateKey;
    }
    console.log("✅ Private Key Decrypted Successfully.");
  } catch (error: any) {
    console.error(`❌ ${error.message}`);
    process.exit(1);
  }

  // 2. Setup Signer using decrypted key
  const provider = ethers.provider;
  const deployer = new ethers.Wallet(privateKey, provider);

  console.log("");
  console.log("═══════════════════════════════════════════════════════════");
  console.log("  🚀 CryptoSwap — Sepolia Testnet Deployment");
  console.log("═══════════════════════════════════════════════════════════");
  console.log(`  Deployer:  ${deployer.address}`);

  const balance = await provider.getBalance(deployer.address);
  const balanceFormatted = ethers.formatEther(balance);
  console.log(`  Balance:   ${balanceFormatted} ETH`);

  if (balance < ethers.parseEther("0.01")) {
    console.log("");
    console.log("  ❌ Insufficient balance! You need at least 0.01 Sepolia ETH.");
    console.log("  📌 Get test ETH from:");
    console.log("     → https://cloud.google.com/application/web3/faucet/ethereum/sepolia");
    process.exit(1);
  }

  console.log("═══════════════════════════════════════════════════════════");
  console.log("");

  // Track deployed addresses for summary
  const deployed: Record<string, string> = {};

  // ════════════════════════════════════════
  //  Step 1: Deploy WETH
  // ════════════════════════════════════════
  console.log("  [1/6] 📦 Deploying WETH (Wrapped Ether)...");
  const WETH = await ethers.getContractFactory("WETH9", deployer);
  const weth = await WETH.deploy();
  await weth.waitForDeployment();
  deployed.WETH = await weth.getAddress();
  console.log(`         ✅ WETH: ${deployed.WETH}`);

  // ════════════════════════════════════════
  //  Step 2: Deploy USDC
  // ════════════════════════════════════════
  console.log("  [2/6] 📦 Deploying USDC (Mock USD Coin)...");
  const MockERC20 = await ethers.getContractFactory("MockERC20", deployer);
  const usdc = await MockERC20.deploy("USD Coin", "USDC", 6);
  await usdc.waitForDeployment();
  deployed.USDC = await usdc.getAddress();
  console.log(`         ✅ USDC: ${deployed.USDC}`);

  // ════════════════════════════════════════
  //  Step 3: Deploy DAI
  // ════════════════════════════════════════
  console.log("  [3/6] 📦 Deploying DAI (Mock Dai)...");
  const dai = await MockERC20.deploy("Dai Stablecoin", "DAI", 18);
  await dai.waitForDeployment();
  deployed.DAI = await dai.getAddress();
  console.log(`         ✅ DAI:  ${deployed.DAI}`);

  // ════════════════════════════════════════
  //  Step 4: Deploy Factory
  // ════════════════════════════════════════
  console.log("  [4/6] 📦 Deploying CryptoSwapFactory...");
  const Factory = await ethers.getContractFactory("CryptoSwapFactory", deployer);
  const factory = await Factory.deploy();
  await factory.waitForDeployment();
  deployed.Factory = await factory.getAddress();
  console.log(`         ✅ Factory: ${deployed.Factory}`);

  // ════════════════════════════════════════
  //  Step 5: Deploy Router
  // ════════════════════════════════════════
  console.log("  [5/6] 📦 Deploying CryptoSwapRouter...");
  const Router = await ethers.getContractFactory("CryptoSwapRouter", deployer);
  const router = await Router.deploy(deployed.Factory, deployed.WETH);
  await router.waitForDeployment();
  deployed.Router = await router.getAddress();
  console.log(`         ✅ Router: ${deployed.Router}`);

  // ════════════════════════════════════════
  //  Step 6: Create & Initialize ETH/USDC Pool
  // ════════════════════════════════════════
  console.log("  [6/6] 📦 Creating ETH/USDC Pool (0.30% fee)...");

  const createTx = await factory.createPool(deployed.WETH, deployed.USDC, 3000);
  await createTx.wait();

  deployed.ETH_USDC_Pool = await factory.getPool(deployed.WETH, deployed.USDC, 3000);
  console.log(`         ✅ Pool:  ${deployed.ETH_USDC_Pool}`);

  console.log("         ⚙️  Initializing pool (1 ETH = 3000 USDC)...");
  const pool = await ethers.getContractAt("CryptoSwapPool", deployed.ETH_USDC_Pool, deployer);

  // sqrtPriceX96 for 3000 USDC/ETH
  const sqrtPriceX96 = BigInt("4339048060990336") * BigInt(2 ** 32);
  const initTx = await pool.initialize(sqrtPriceX96);
  await initTx.wait();
  console.log("         ✅ Pool initialized!");

  // Mint test tokens
  console.log("");
  console.log("  🏭 Minting test tokens...");
  await (await usdc.mint(deployer.address, ethers.parseUnits("100000", 6))).wait();
  await (await dai.mint(deployer.address, ethers.parseEther("100000"))).wait();


  // ════════════════════════════════════════
  //  Summary
  // ════════════════════════════════════════
  console.log("");
  console.log("═══════════════════════════════════════════════════════════");
  console.log("  📋 DEPLOYMENT SUMMARY — Sepolia Testnet");
  console.log("═══════════════════════════════════════════════════════════");
  console.log("");
  console.log("  Contract Addresses:");
  Object.entries(deployed).forEach(([name, address]) => {
    const paddedName = name.padEnd(15);
    console.log(`    ${paddedName} ${address}`);
  });
  console.log("");
  console.log("  🔗 View on Etherscan:");
  Object.entries(deployed).forEach(([name, address]) => {
    console.log(`    ${name}: https://sepolia.etherscan.io/address/${address}`);
  });
  console.log("");
  console.log("  📝 Next Steps:");
  console.log("    1. Verify contracts: npx hardhat verify --network sepolia <ADDRESS>");
  console.log("    2. Save these addresses for your frontend .env");
  console.log("    3. Test a swap using the Router contract on Etherscan");
  console.log("");
  console.log("  💾 Saving addresses to deployed-addresses.json...");

  // Save to file for easy reference
  const fs = require("fs");
  const deploymentInfo = {
    network: "sepolia",
    chainId: 11155111,
    deployedAt: new Date().toISOString(),
    deployer: deployer.address,
    contracts: deployed,
    urls: Object.fromEntries(
      Object.entries(deployed).map(([name, addr]) => [
        name,
        `https://sepolia.etherscan.io/address/${addr}`
      ])
    )
  };
  fs.writeFileSync(
    "deployed-addresses.json",
    JSON.stringify(deploymentInfo, null, 2)
  );
  console.log("  ✅ Saved to deployed-addresses.json");
  console.log("");
  console.log("═══════════════════════════════════════════════════════════");
  console.log("  🎉 Deployment complete! Your AMM is live on Sepolia!");
  console.log("═══════════════════════════════════════════════════════════");
  console.log("");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("");
    console.error("  ❌ Deployment failed!");
    console.error("");
    console.error("  Error:", error.message);
    console.error("");

    if (error.message.includes("insufficient funds")) {
      console.error("  💡 You need more Sepolia ETH. Get some from:");
      console.error("     → https://cloud.google.com/application/web3/faucet/ethereum/sepolia");
    } else if (error.message.includes("could not detect network")) {
      console.error("  💡 Check your SEPOLIA_RPC_URL in .env file.");
      console.error("     Make sure it's a valid Alchemy/Infura URL.");
    } else if (error.message.includes("invalid account")) {
      console.error("  💡 Check your PRIVATE_KEY in .env file.");
      console.error("     It should start with 0x and be 66 characters.");
    }

    process.exit(1);
  });
