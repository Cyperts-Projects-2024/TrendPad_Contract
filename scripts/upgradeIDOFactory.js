// scripts/upgrade-factory.js
const { ethers, upgrades } = require("hardhat");

async function main() {
  const proxyAddress = "0xfb49Ae650f86EF7EE375B86C9ef31A29338980c0";
  const TrendPadFactoryV2 = await ethers.getContractFactory("TrendPadIDOFactoryV3");

  console.log("Upgrading TrendPadFactory...");
  const upgraded = await upgrades.upgradeProxy(proxyAddress, TrendPadFactoryV2);

  console.log("✅ Upgrade complete at:", upgraded.address);
}

main();
