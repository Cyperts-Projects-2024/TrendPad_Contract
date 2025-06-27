const hre = require("hardhat");
const { ethers } = hre;

async function main() {
  const [signer] = await ethers.getSigners();

  const ii2 = await ethers.getContractAt(
    "BuyBackManager",
    "0x0d8cD046b1885e58a5c10e21ef8041E711C7fe60", // Replace with your real address
    signer
  );

  const poolAddress = "0x697379544dc71f51A4306c0c36445AC34c983029";
  const tokenA = "0xCB34f3Bb2ccaf5ef8aa21197c44Ed0973a362FF8";
  const tokenB = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const router = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";

  const softCap = ethers.parseUnits("1", 6); // 1 USDT
  const buyBackPercent = 5;

  const totalBuyBackAmount = 50000;
  console.log("Calculated Buyback Amount:", totalBuyBackAmount.toString());

  const tx = await ii2.setBuybackConfig(
    poolAddress,
    tokenA,
    tokenB,
    router,
    buyBackPercent,
    totalBuyBackAmount,
    true
  );

  console.log("Tx hash:", tx.hash);
  await tx.wait();
  console.log("✅ Buyback config set successfully.");
}

main().catch((error) => {
  console.error("❌ Error setting buyback config:", error);
  process.exit(1);
});
