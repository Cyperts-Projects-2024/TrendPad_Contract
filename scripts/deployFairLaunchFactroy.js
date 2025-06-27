const { ethers, upgrades } = require("hardhat");

async function main() {
  // const signers = await ethers.getSigners();
  const TA = await ethers.getContractFactory("TrendPadIDOFairLaunchFactoryV2");
  const gasOverrides = {
    gasLimit: ethers.parseUnits("5000000", "wei"), // Adjust as needed
    gasPrice: ethers.parseUnits("50", "gwei")      // Adjust gas price for your network
  };
  const platformFee=ethers.parseUnits("0.001", 18); // 1% platform fee
  const buyBackManager ="0x073bc8E5978DD102dE61e167fE608a09e8160d92"
  const  fairlaunchpool ="0x28968c0d968106f2e7461f6f885fc998172864d2"
  const fairLaunchERC20="0x99c236Bcb260d69Fb7d59e0Ab2aBA724dd978BE4"
  const ta = await upgrades.deployProxy(TA, [
    "3",
    "0xA457e51Dd27D2D250A4B2944b2f70a3447E4B73b",platformFee,
    fairlaunchpool,fairLaunchERC20,buyBackManager

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