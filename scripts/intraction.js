const { ethers } = require("hardhat");

	async function main() {
	  const signer = (await ethers.getSigners())[0];
	  const nonce = await signer.getNonce();

	    const [deployer] = await ethers.getSigners();
	  
	    // First, check your token balance and approve the transfer
	    const token = await ethers.getContractAt("ERC20", "0xCB34f3Bb2ccaf5ef8aa21197c44Ed0973a362FF8");
		const Currency= await ethers.getContractAt("ERC20", "0xBF502baAff686F57b53a8CFf799c1734eaf3D629");
	    
	    // Check your balance first0x7a781c4aBaf94d019fba17Eb7a9e17E4Bce0345F
	    const balance = await token.balanceOf(deployer.address);
	    console.log("Your token balance:", ethers.formatUnits(balance, "ether"));
	    
	    // Get token decimals
	    const decimals = await token.decimals();
		const currencyDecimals = await Currency.decimals();
	    
	    // Calculate required tokens
	    const hardCap = ethers.parseUnits("0.04",currencyDecimals);
	    const tokenPrice = ethers.parseUnits("1000", decimals);
	    const listingPrice = ethers.parseUnits("500", decimals); // 500 tokens per BUSD
	    const lpInterestRate = 60;
	    
	    // Calculate presale tokens (hardCap * tokenPrice / 10^decimals)
	    const presaleTokens = (hardCap * tokenPrice) / (10n ** BigInt(currencyDecimals));
		console.log("Presale tokens required:",hardCap, tokenPrice);
	 
         console.log("Presale tokens required:", ethers.formatUnits(presaleTokens, decimals));
	    
	    // Calculate LP tokens (hardCap * lpInterestRate/100 * listingPrice / 10^decimals)
		const lpTokens = ((hardCap * BigInt(lpInterestRate) / 100n) * listingPrice) / (10n ** BigInt(currencyDecimals));

		console.log("LP tokens required:", ethers.formatUnits(lpTokens, decimals));
	    const lpTokenAmount =lpTokens
	    // console.log("LP tokens required:", ethers.formatUnits(lpTokenAmount, "ether"));
	    
	    // Total tokens needed
	    const totalTokensNeeded = presaleTokens + lpTokenAmount;
	    console.log("Total tokens required:", ethers.formatUnits(totalTokensNeeded, "ether"));
	    
	    // Check if you have enough tokens
	    if (balance < totalTokensNeeded) {
		console.error("Error: Not enough tokens in your wallet!");
		console.log(`You need ${ethers.formatUnits(totalTokensNeeded, "ether")} tokens but only have ${ethers.formatUnits(balance, "ether")}`);
		return;
	    }
	    console.log("Approved token transfer o");
	    
	    // Approve the transfer with a small buffer
	    // const approveAmount = totalTokensNeeded * 102n / 100n; // Add 2% buffer just in case
	    // const approveTx = await token.approve(
	    //     "0xfb49Ae650f86EF7EE375B86C9ef31A29338980c0", 
	    // approveAmount,{
	    // nonce:nonce,
		// gasLimit: 5000000,  // Increase gas limit
		// gasPrice: ethers.parseUnits("10", "gwei") 
		// 	}
	    // );
	    // await approveTx.wait();
	    // console.log("Approved token transfer of", ethers.formatUnits(approveAmount, "ether"), "tokens");
	  
	    // Now create the IDO with 60% LP interest rate
	    const factory = await ethers.getContractAt("TrendPadIDOFactoryV3", "0xfb49Ae650f86EF7EE375B86C9ef31A29338980c0");
	  
	    const saleInfo = {
		  Currency :"0xBF502baAff686F57b53a8CFf799c1734eaf3D629", // BUSD
	      rewardToken: "0xCB34f3Bb2ccaf5ef8aa21197c44Ed0973a362FF8",
	      presaleToken: presaleTokens,
	      liquidityToken: lpTokenAmount,
	      tokenPrice: ethers.parseUnits("1000", decimals), // 1000 tokens per BUSD
		  softCap: ethers.parseUnits("0.01", currencyDecimals),
		  hardCap: ethers.parseUnits("0.04", currencyDecimals),
		  minEthPayment: ethers.parseUnits("0.01", currencyDecimals),
		  maxEthPayment: ethers.parseUnits("0.02", currencyDecimals),		  
	      listingPrice: ethers.parseUnits("500", decimals), // 500 tokens per BUSD
	      lpInterestRate: lpInterestRate, 
	      burnType: false,
	      affiliation: false,
	      isEnableWhiteList: false,
		 isVestingEnabled:false
	    };
	    
	    const timestamps = {
	      startTimestamp: Math.floor(Date.now() / 1000) + 720,
	      endTimestamp: Math.floor(Date.now() / 1000) + 1800,
	      claimTimestamp: 0,
	      unlockTime: 180
	    };

	    const dexInfo = {
	      router: "0xD99D1c33F9fC3444f8101754aBC46c52416550D1",
	      factory: "0x6725F303b657a9451d8BA641348b6761A6CC7a17",
	      weth: "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd"
	    };
const VestingInfo ={
	TGEPercent:0,
    cycleTime:0,
	releasePercent:0,
	startTime:0
}

	  
	    console.log("Creating IDO...");
	    const tx = await factory.createIDOERC20(
	      saleInfo,
	      timestamps,
	      dexInfo,
		  VestingInfo,	
	      "0x880674380d2818dE6B0b642Ca4D995C20A51D7B3",
		  0,
	      { 
		nonce:nonce,
		gasLimit: 5000000,  // Increase gas limit
		gasPrice: ethers.parseUnits("11", "gwei")  // Increase gas price
	      }
	    );
	  
	    console.log("Transaction sent, waiting for confirmation...");
	    const receipt = await tx.wait();
	    console.log("Transaction confirmed!");
	    
	    // Find the IDO created event
	    const createdEvents = await factory.queryFilter(
	      factory.filters.IDOCreated(),
	      receipt.blockNumber,
	      receipt.blockNumber
	    );
	    
	    if (createdEvents.length > 0) {
	      console.log("🎉 New IDO (TrendPool) deployed at:", createdEvents[0].args.TrendPool);
	    } else {
	      console.log("Event not found. Check TrendPools array for the new pool.");
	      const pools = await factory.getTrendPools();
	      console.log("Latest pool:", pools[pools.length - 1]);
	    }
	  }
	  
	  main().catch(console.error);
	  40000000000000