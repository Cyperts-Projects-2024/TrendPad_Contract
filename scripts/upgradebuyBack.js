const {ethers,upgrades} = require("hardhat");

async function main() {
    const proxyAddress = "0xE2371005C941011aD5C058B995C38A9aEc9E97E1"; // Replace with your deployed contract address
    const TrendFairLuanchv2 = await ethers.getContractFactory("BuyBackManager");

    console.log("Upgrading TrendPool...");
    const upgraded = await upgrades.upgradeProxy(proxyAddress, TrendFairLuanchv2);

    console.log("✅ Upgrade complete at:", upgraded.address);
}
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});