const { ethers, upgrades } = require("hardhat");

async function main() {
  try {
    console.log("\n🚀 Starting BuyBackManager deployment...");

    // 1. Get contract factory
    const BuyBackManager = await ethers.getContractFactory("BuyBackManagerV2");
    
    // 2. Configure deployment parameters
    const deploymentParams = {
      amountPerBuyBack: ethers.parseEther("0.001"), // 0.001 ETH
      minBuyBackDelay: 60,    // 1 minute (in seconds)
      maxBuyBackDelay: 300,   // 5 minutes (in seconds)
      gasSettings: {
        maxFeePerGas: ethers.parseUnits("50", "gwei"),
        maxPriorityFeePerGas: ethers.parseUnits("2", "gwei"),
        gasLimit: 5_000_000
      }
    };

    // 3. Deploy proxy
    console.log("\n🔨 Deploying proxy...");
    const buyBack = await upgrades.deployProxy(
      BuyBackManager,
      [
        deploymentParams.amountPerBuyBack,
        deploymentParams.minBuyBackDelay,
        deploymentParams.maxBuyBackDelay
      ],
      {
        kind: "uups",
        txOverrides: deploymentParams.gasSettings,
        timeout: 180000, // 3 minutes
        pollingInterval: 10000 // 10 seconds
      }
    );

    // 4. Wait for deployment
    console.log("\n⏳ Waiting for deployment confirmation...");
    await buyBack.waitForDeployment();
    
    // 5. Get deployment details
    const proxyAddress = await buyBack.getAddress();
    const implementationAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress);
    
    console.log("\n✅ Deployment successful!");
    console.log(`Proxy address: ${proxyAddress}`);
    console.log(`Implementation address: ${implementationAddress}`);

    // 6. Prepare verification command
    console.log("\n📋 Verification command:");
    console.log(`npx hardhat verify --network YOUR_NETWORK ${proxyAddress} \\
      "${deploymentParams.amountPerBuyBack.toString()}" \\
      "${deploymentParams.minBuyBackDelay}" \\
      "${deploymentParams.maxBuyBackDelay}"`);

  } catch (error) {
    console.error("\n❌ Deployment failed:", error);
    process.exit(1);
  }
}

main();