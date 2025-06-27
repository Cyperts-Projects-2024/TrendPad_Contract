const { ethers, upgrades } = require("hardhat");

async function main() {
const TrendFairlaunchERC20Pool = await ethers.getContractFactory("TrendFairlaunchERC20PoolV2");
const signer = (await ethers.getSigners())[0];
const nonce = await signer.getNonce();
  // Deploy the contract
  const token = await TrendFairlaunchERC20Pool.deploy({
    initializer: false,
    nonce,
    gasPrice: ethers.parseUnits("40", "gwei"),
  });
   
  await token.waitForDeployment();  
  // Get the deployed address
  const implAddress = await token.getAddress();
  console.log("✅ TrendPool Implementation deployed at:", implAddress);
}

main().catch((error) => {
  console.error("❌ Deployment failed:", error);
  process.exitCode = 1;
});
// 0x663324FBfa7a395510F9f6BfE8AA8a9c596c022B  first deploy
//0xDEf4dB1f45EEEc6d599a0311b9e0dF6A80288690 Date :2025-05-18
// 0xAb6792D1e4221c5c21B6d78C3aD6c1Ab97c42360 Date :2025-05-19
//0x2b01607985c073Bf6F0CC6c54416d0fA2eE4594D
// 0xaf072d3189d34c7e953860128b36034d418e5b54