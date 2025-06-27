// scripts/deploy.js
const { ethers, upgrades } = require("hardhat");

async function main() {
  try {
    console.log("\nStarting deployment...");
    
    // 1. Configure deployment parameters
    const [deployer] = await ethers.getSigners();
    console.log(`Deployer: ${deployer.address}`);
    console.log(`Balance: ${ethers.formatEther(await deployer.provider.getBalance(deployer.address))} ETH`);

    const deploymentParams = {
      platformFee: ethers.parseEther("0.001"), // 0.001 ETH
      feeWallet: "0xA457e51Dd27D2D250A4B2944b2f70a3447E4B73b",
      implementation: "0x1F4529B0Ac0f769f575eD69e08cF944636B377E4",
      gasSettings: {
        maxFeePerGas: ethers.parseUnits("50", "gwei"), // Adjust based on network conditions
        maxPriorityFeePerGas: ethers.parseUnits("2", "gwei"),
        gasLimit: 3_000_000
      }
    };

    // 2. Deploy the proxy
    console.log("\nDeploying AirdropFactory proxy...");
    const AirdropFactory = await ethers.getContractFactory("AirdropFactoryV1");
    
    const factory = await upgrades.deployProxy(
      AirdropFactory,
      [
        deploymentParams.platformFee,
        deploymentParams.feeWallet,
        deploymentParams.implementation
      ],
      {
        kind: "uups",
        txOverrides: deploymentParams.gasSettings,
        timeout: 180000, // 3 minutes
        pollingInterval: 10000 // 10 seconds
      }
    );

    // 3. Wait for deployment confirmation
    console.log("\nTransaction sent, waiting for confirmation...");
    const deploymentReceipt = await factory.waitForDeployment();
    console.log(`\n✅ Deployment successful!`);
    console.log(`Factory address: ${await factory.getAddress()}`);
    console.log(`Tx hash: ${deploymentReceipt.deploymentTransaction().hash}`);

    // 4. Verification preparation
    console.log("\nPrepare for verification with:");
    console.log(`npx hardhat verify --network YOUR_NETWORK ${await factory.getAddress()} \\
      "${deploymentParams.platformFee.toString()}" \\
      "${deploymentParams.feeWallet}" \\
      "${deploymentParams.implementation}"`);

  } catch (error) {
    console.error("\n❌ Deployment failed:", error);
    process.exit(1);
  }
}

main()