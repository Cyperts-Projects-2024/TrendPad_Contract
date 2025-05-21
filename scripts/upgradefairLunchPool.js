const {ethers,upgrades} = require("hardhat");

async function main() {
    const proxyAddress = "0x663324FBfa7a395510F9f6BfE8AA8a9c596c022B"; // Replace with your deployed contract address
    const TrendFairLuanchv2 = await ethers.getContractFactory("TrendFairlaunchPoolV2");

    console.log("Upgrading TrendPool...");
    const upgraded = await upgrades.upgradeProxy(proxyAddress, TrendFairLuanchv2);

    console.log("✅ Upgrade complete at:", upgraded.address);
}
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});