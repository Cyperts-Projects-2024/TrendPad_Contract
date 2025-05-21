const {ethers,upgrades} = require("hardhat");

async function main() {
    const proxyAddress = "0xb2b1b47Ca42D6aEB8810cfA28c555382d62Ae32C"; // Replace with your deployed contract address
    const TrendFairLuanchv2 = await ethers.getContractFactory("TrendPadIDOFairLaunchFactoryV2");

    console.log("Upgrading TrendPool...");
    const upgraded = await upgrades.upgradeProxy(proxyAddress, TrendFairLuanchv2);

    console.log("✅ Upgrade complete at:", upgraded.address);
}
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});