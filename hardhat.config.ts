import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";

dotenv.config();

/**
 * 🔒 SECURITY: HELPER TO PREVENT CRASHING ON ENCRYPTED KEYS
 * If the PRIVATE_KEY is encrypted (base64) instead of raw hex, 
 * Hardhat config validation will fail. This helper ensures we only 
 * pass valid hex keys to the config, while allowing the deployment
 * script to handle manual decryption.
 */
const getAccounts = (): string[] => {
  const pk = process.env.PRIVATE_KEY;
  if (!pk) return [];
  
  // Only return if it looks like a 64-char hex string (optionally starts with 0x)
  const isHex = /^(0x)?[0-9a-fA-F]{64}$/.test(pk);
  if (isHex) {
    return [pk.startsWith("0x") ? pk : `0x${pk}`];
  }
  
  // If it's encrypted or invalid, return empty so config stays valid.
  // The custom deployment script (deploy-sepolia.ts) will handle the error/decryption.
  return [];
};

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
    },
  },
  networks: {
    hardhat: {
      chainId: 31337,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337,
    },
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: getAccounts(),
      chainId: 11155111,
    },
    arbitrumOne: {
      url: process.env.ARBITRUM_RPC_URL || "",
      accounts: getAccounts(),
      chainId: 42161,
    },
    optimism: {
      url: process.env.OPTIMISM_RPC_URL || "",
      accounts: getAccounts(),
      chainId: 10,
    },
  },
  etherscan: {
    apiKey: {
      sepolia: process.env.ETHERSCAN_API_KEY || "",
      arbitrumOne: process.env.ARBISCAN_API_KEY || "",
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS === "true",
    currency: "USD",
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
};

export default config;
