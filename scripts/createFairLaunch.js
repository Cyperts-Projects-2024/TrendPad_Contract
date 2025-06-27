const { ethers } = require("hardhat");

async function main() {
  const signer = (await ethers.getSigners())[0];
  const nonce = await signer.getNonce();
  const [deployer] = await ethers.getSigners();

  const token = await ethers.getContractAt("ERC20", "0xCB34f3Bb2ccaf5ef8aa21197c44Ed0973a362FF8");

  const balance = await token.balanceOf('0xcE55f07CB6BC9cfE386675887A96215DEf209e20');
  console.log("Your token balance:", ethers.formatUnits(balance, "ether"));

  const decimals = await token.decimals();

  const softCap = ethers.parseUnits("0.01", 6); // 0.01 BNB
  const tokenAmount = ethers.parseUnits("1000", "ether");
  const lpInterestRate = 51;

  console.log("Fairlaunch tokens required:", ethers.formatUnits(tokenAmount, "ether"));

  const ethAmount = ethers.parseUnits("0.001", 18);
  console.log("ETH amount required:", ethAmount.toString());

  const factory = await ethers.getContractAt("TrendPadIDOFairLaunchFactoryV2", "0x7fb4b7872be0a7b44c9796b28165e29b4fd45716");
  const lpTokenAmount = await factory.getFairLaunchTokenAmount(tokenAmount, lpInterestRate, 6);

  console.log("LP tokens required:", lpTokenAmount.toString());

  const totalTokensNeeded = tokenAmount + lpTokenAmount;
  console.log("Total tokens required:", ethers.formatUnits(totalTokensNeeded, "ether"));

  if (balance < totalTokensNeeded) {
    console.error("❌ Error: Not enough tokens in your wallet!");
    console.log(`You need ${ethers.formatUnits(totalTokensNeeded, "ether")} tokens but only have ${ethers.formatUnits(balance, "ether")}`);
    return;
  }

      //     // Approve the transfer with a small buffer
      //   const approveAmount = totalTokensNeeded * 102n / 100n; // Add 2% buffer just in case
      //   const approveTx = await token.approve(
      //       "0x7fb4b7872be0a7b44c9796b28165e29b4fd45716", 
      //       approveAmount,{
      //  nonce:nonce+1,
    	// gasLimit: 4000000,  // Increase gas limit
    	// gasPrice: ethers.parseUnits("12", "gwei") 
    	// 	}
      //   );
      //   await approveTx.wait();
      //   console.log("Approved token transfer of", ethers.formatUnits(approveAmount, "ether"), "tokens");
      

      const allowance = await token.allowance(
        deployer.address,                          // Owner (your wallet address)
        "0x7fb4b7872be0a7b44c9796b28165e29b4fd45716" // Spender (Factory contract)
      );
      
      console.log("Allowance:", ethers.formatUnits(allowance, "ether"));
      

  console.log("✅ Token balance is sufficient");
  const currentTime = Math.floor(Date.now() / 1000);

  // === Sale Config ===
  const params = {
    _saleInfo: {
      currency: '0xdBc5a5edF4E43553023C9a5B5b35c0ce410459B6', // ETH
      saleToken: '0xCB34f3Bb2ccaf5ef8aa21197c44Ed0973a362FF8',
      tokenAmount: ethers.parseEther("1000"),
      liquidityToken:lpTokenAmount,
     
      softCap: softCap,
      maxPay: ethers.parseUnits("0.02",6),
      lpPercent: 51, // Must be 0 or >= 51
      isBuyBackEnabled: false,  
      isVestingEnabled: false,
      isAffiliatationEnabled: true,
      isEnableWhitelist: false,
    },
    _timestamps: {
      startTimestamp: currentTime + 3600, // 1 hour from now
      endTimestamp: currentTime + 86400, // 24 hours from now
      unlockTime: 600, // 10 minutes (or 0)
      claimTimestamp: currentTime + 86400, // Same as endTimestamp
    },
    _dexInfo: {
      router: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", // Uniswap Router
      factory: "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f", // Uniswap Factory
      weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", // Mainnet WETH
    },
    _vestingInfo: {
      TGEPercent: 0,
      cycleTime: 0,
      releasePercent: 0,
      startTime: 0,
    },
    _lokerFactoryAddress: "0x7fb4b7872be0a7b44c9796b28165e29b4fd45716", // Locker factory (if used)
    _affiliateRate: 3,
    _buyBackPercent: 0,
  };

  console.log("🚀 Creating IDO...");

  try {
    await factory.createFairLaunch(
      params._saleInfo,
      params._timestamps,
      params._dexInfo,
      params._vestingInfo,
      params._lokerFactoryAddress,
      params._affiliateRate,
      params._buyBackPercent,
      { value: ethers.parseEther("0.001") } // Adjust to platformFee
    );

    console.log("⏳ Transaction sent. Waiting for confirmation...");
    const receipt = await tx.wait();
    console.log("✅ Transaction confirmed at block:", receipt.blockNumber);

    const createdEvents = await factory.queryFilter(
      factory.filters.IDOCreated(),
      receipt.blockNumber,
      receipt.blockNumber
    );

    if (createdEvents.length > 0) {
      console.log("🎉 New IDO (TrendPool) deployed at:", createdEvents[0].args.TrendPool);
    } else {
      console.warn("⚠ IDO event not found. Try checking getTrendPools()");
    }

  } catch (error) {
    console.error("❌ Transaction Failed!");

    if (error?.reason) {
      console.error("Revert reason:", error.reason);
    }

    if (error?.error?.message) {
      console.error("Inner error message:", error.error.message);
    }

    if (error?.data?.message) {
      console.error("Data error message:", error.data.message);
    }

    if (error?.transaction) {
      console.error("Transaction details:", {
        to: error.transaction.to,
        data: error.transaction.data,
        gasLimit: error.transaction.gasLimit?.toString(),
        value: error.transaction.value?.toString(),
      });
    }

    console.error("📜 Full error stack:");
    console.error(error);
  }
}

main().catch(console.error);
