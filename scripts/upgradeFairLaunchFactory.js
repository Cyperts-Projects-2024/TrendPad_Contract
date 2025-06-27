const {ethers,upgrades} = require("hardhat");

async function main() {
    const proxyAddress = "0x7fb4b7872be0a7b44c9796b28165e29b4fd45716"; // Replace with your deployed contract address
    const TrendFairLuanchv2 = await ethers.getContractFactory("TrendPadIDOFairLaunchFactoryV2");

    console.log("Upgrading TrendPool...");
    const upgraded = await upgrades.upgradeProxy(proxyAddress, TrendFairLuanchv2);

    console.log("✅ Upgrade complete at:", upgraded.address);
}
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});