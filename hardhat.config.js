/**
 * @type import('hardhat/config').HardhatUserConfig
 */

require("dotenv").config();
require("@nomicfoundation/hardhat-toolbox");
require("hardhat-contract-sizer");

module.exports = {
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
  etherscan: {
    // API key for verifying contracts (can be set in the .env file)
    apiKey: process.env.ETHERSCAN_API_KEY || "RAR24WSTVR5AZJAVFNQIWY76KY4P7PDW5Y",
  },
  // Set the default network based on an environment variable or fallback to `hardhat`
  defaultNetwork: process.env.DEFAULT_NETWORK || "hardhat",
  solidity: {
    version: "0.8.26", // Specify Solidity version
    settings: {
      optimizer: {
        enabled: true, // Enable optimizer for efficient gas usage
        runs: 200,
      },
    },
  },
  networks: {
    hardhat: {
      chainId: 31337, // Default chain ID for Hardhat
      // Optional settings for Hardhat network
      allowUnlimitedContractSize: true, // Useful for debugging large contracts
      blockGasLimit: 12000000, // Set higher gas limit if needed
    },
    testnet: {
      url: process.env.TESTNET_RPC || "https://data-seed-prebsc-2-s1.binance.org:8545/", // Use environment variable or fallback to localhost
      chainId: 97,
      loggingEnabled: true, // Enable verbose logging for Hardhat network

      // Adjust to the correct chain ID for the testnet
      accounts: [
        process.env.PRIVATE_KEY ||
        "6df6f949962d16815e3b5f9c420d451f894eea3b752ddcd836f612c7c83a21db",
      ],
    },

    // Uncomment and configure for mainnet
    // mainnet: {
    //   url: process.env.MAINNET_RPC || "",
    //   chainId: 1,
    //   accounts: [process.env.PRIVATE_KEY || ""],
    // },
  },
};
