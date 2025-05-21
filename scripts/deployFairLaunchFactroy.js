const { ethers, upgrades } = require("hardhat");

async function main() {
  // const signers = await ethers.getSigners();
  const TA = await ethers.getContractFactory("TrendPadIDOFairLaunchFactory");
  const gasOverrides = {
    gasLimit: ethers.parseUnits("5000000", "wei"), // Adjust as needed
    gasPrice: ethers.parseUnits("50", "gwei")      // Adjust gas price for your network
  };
  const ta = await upgrades.deployProxy(TA, [
    "5",
    "0xA457e51Dd27D2D250A4B2944b2f70a3447E4B73b"
  ],gasOverrides);
  await ta.waitForDeployment();
  console.log(`TTAvatars Address: `, await ta.getAddress());
  console.log("TTAvatars", ta);
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});



// npx hardhat run --network localhost scripts/deploy_TA.js

// npx hardhat run --network testnet scripts/deploy_TA.js

// npx hardhat verify --network testnet {contractaddress}