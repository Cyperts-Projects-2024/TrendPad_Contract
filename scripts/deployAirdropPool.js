// scripts/deploy.js
const { ethers, upgrades } = require("hardhat");

async function main() {
  // Deploy the implementation contract first
  const AirdropPool = await ethers.getContractFactory("AirdropPool");
  console.log("Deploying AirdropPool implementation...");
  const airdropPoolImpl = await upgrades.deployImplementation(AirdropPool);
  console.log("AirdropPool implementation deployed to:", airdropPoolImpl);

//   // Deploy the factory proxy
//   const AirdropFactory = await ethers.getContractFactory("AirdropFactory");
//   console.log("Deploying AirdropFactory...");
  
//   const platformFee = ethers.utils.parseEther("0.1"); // 0.1 ETH platform fee
//   const feeWallet = "0xYourFeeWalletAddress"; // Replace with actual address
  
//   const factory = await upgrades.deployProxy(AirdropFactory, [
//     platformFee,
//     feeWallet,
//     airdropPoolImpl
//   ]);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });