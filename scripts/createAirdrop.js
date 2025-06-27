const { ethers } = require("hardhat");

async function main() {
  // Replace with deployed AirdropFactory proxy address
  const factoryAddress = "0xaED15e74124240577Fc6DD2944F2cFC360C2f49B"; 
  
  // Replace with ERC20 token address you want to use for airdrop
  const tokenAddress = "0x608B77eDD2e13eA300A0FE912728F69e5A3E7DED"; 
  
  // Replace with a sample metadata URL for the pool
  const metaUrl = "https://example.com/airdrop-meta.json";

  // Define the platform fee (same as in factory contract)
  const platformFee = ethers.parseEther("0.001"); // 0.001 ETH

  const [deployer] = await ethers.getSigners();
  console.log(`Using account: ${deployer.address}`);

  const AirdropFactory = await ethers.getContractFactory("AirdropFactoryV1");
  const factory = await AirdropFactory.attach(factoryAddress);

  console.log("Creating airdrop pool...");

  const tx = await factory.createAirdrop(
    tokenAddress,
    metaUrl,
    {
      value: platformFee, // sending ETH as fee
      gasLimit: 5000000,
    }
  );

  const receipt = await tx.wait();
  console.log("Airdrop pool created!",receipt);

}

main().catch((error) => {
  console.error("❌ Error creating airdrop:", error);
  process.exit(1);
});
