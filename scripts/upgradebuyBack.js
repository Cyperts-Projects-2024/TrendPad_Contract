const { ethers, upgrades } = require("hardhat");

async function main() {
  const proxyAddress = "0x8452A89aF7E0A054B60C8bc29AbF01121D2E1e9d"; // Deployed UUPS proxy address
  const BuyBackManager = await ethers.getContractFactory("BuyBackManagerV2");

  console.log("⏳ Importing proxy as UUPS...");
  await upgrades.forceImport(proxyAddress, BuyBackManager, {
    kind: "uups",
  });

  console.log("🔁 Upgrading BuyBackManager...");
  const upgraded = await upgrades.upgradeProxy(proxyAddress, BuyBackManager, {
    kind: "uups",
  });

  console.log("✅ Upgrade complete. Proxy address:", upgraded.address);
}

main().catch((error) => {
  console.error("❌ Error during upgrade:", error);
  process.exitCode = 1;
});
