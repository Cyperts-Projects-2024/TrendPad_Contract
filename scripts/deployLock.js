const {ethers, upgrades} = require("hardhat");

async function main (){
    const [deployer]=await ethers.getSigners();
    console.log("🚀 Deploying contracts with account:", deployer.address);

    const TrendLock = await ethers.getContractFactory("TrendLock");

    const trendLock= await TrendLock.deploy({
        gasLimit: 5000000,
        gasPrice: ethers.parseUnits("10", "gwei")
    });
    await trendLock.waitForDeployment();
    console.log("✅ TrendLock deployed to:", await trendLock.getAddress());
}
main().catch((error) => {
    console.error("❌ Error deploying contract:", error);
    process.exitCode = 1;
});
// Compare this snippet from scripts/deployTrendERC20Pool.js: