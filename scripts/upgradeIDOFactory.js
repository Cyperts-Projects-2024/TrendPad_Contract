// scripts/upgrade-factory.js
const { ethers, upgrades } = require("hardhat");

async function main() {
  const proxyAddress = "0xd6f933A2A6701d68f87b316235B644A9420e11b9";
  const TrendPadFactoryV2 = await ethers.getContractFactory("TrendPadIDOFactoryV2");

  console.log("Upgrading TrendPadFactory...");
  const upgraded = await upgrades.upgradeProxy(proxyAddress, TrendPadFactoryV2);

  console.log("✅ Upgrade complete at:", upgraded.address);
}

main();
