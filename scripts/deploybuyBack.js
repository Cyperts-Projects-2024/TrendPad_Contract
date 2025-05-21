const{ethers, upgrades} = require("hardhat");

async function main(){

    const buyBackManager = await ethers.getContractFactory("BuyBackManager");
    const gasOverrides = {
        gasLimit: ethers.parseUnits("5000000", "wei"), // Adjust as needed
        gasPrice: ethers.parseUnits("50", "gwei")      // Adjust gas price for your network
      };
      const buyBack= await upgrades.deployProxy(buyBackManager, [
        ethers.parseUnits("0.001", "ether"),
        60,
        300
      ],gasOverrides);
      await buyBack.waitForDeployment();
      console.log(`BuyBackManager Address: `, await buyBack.getAddress());

}
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
// npx hardhat run --network localhost scripts/deploybuyBack.js
// npx hardhat run --network testnet scripts/deploybuyBack.js