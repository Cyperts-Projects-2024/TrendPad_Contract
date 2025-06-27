// scripts/deployImplementation.js
const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  
  console.log("Deploying TrendPool implementation with account:", deployer.address);

  const TrendERC20Pool = await ethers.getContractFactory("TrendERC20PoolV2");
  const implementation = await TrendERC20Pool.deploy({
    gasLimit: 4000000,
    gasPrice: ethers.parseUnits("10", "gwei")
  });
  
  await implementation.waitForDeployment();
  console.log("TrendPool implementation deployed to:", await implementation.getAddress());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });