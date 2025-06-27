const { ethers, upgrades } =require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("🚀 Deploying contracts with account:", deployer.address);

  const feePercent = 3; // Example: 2%
  const feeWallet = "0xA457e51Dd27D2D250A4B2944b2f70a3447E4B73b"; // Replace with actual wallet address

  const platformFee = ethers.parseUnits("0.0001", 18);


  const TrendPooladdress="0x0Fd69253f4741A95D110d035B53FB3d44Cb38a9c";
  const TrendERCPoolAddress="0x23F271C866C88a19bac5Dd5Ef43B2c1212C82388";

  const TrendPadIDOFactoryV3 = await ethers.getContractFactory("TrendPadIDOFactoryV3");

  const factory = await upgrades.deployProxy(
    TrendPadIDOFactoryV3,
    [feePercent, feeWallet, platformFee,TrendPooladdress, TrendERCPoolAddress],
    {
      initializer: "initialize",
      kind: "uups",
    },
    { gasLimit: 3000000, gasPrice: ethers.parseUnits("10", "gwei") }
  );

  await factory.waitForDeployment();

  const proxyAddress = await factory.getAddress();
  console.log("✅ TrendPadIDOFactoryV2 deployed to:", proxyAddress);
}

main().catch((error) => {
  console.error("❌ Error deploying contract:", error);
  process.exitCode = 1;
});
