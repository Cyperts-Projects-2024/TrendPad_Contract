const { ethers } = require("hardhat");

    async function main() {
      const signer = (await ethers.getSigners())[0];
      const nonce = await signer.getNonce();

        const [deployer] = await ethers.getSigners();
      
        // First, check your token balance and approve the transfer
        const token = await ethers.getContractAt("ERC20", "0xCB34f3Bb2ccaf5ef8aa21197c44Ed0973a362FF8");
        
        // Check your balance first0x7a781c4aBaf94d019fba17Eb7a9e17E4Bce0345F
        const balance = await token.balanceOf('0xdC49Ee842C4cc6012497d0fbAd232fE51c4d9477');
        console.log("Your token balance:", ethers.formatUnits(balance, "ether"));
        
        // Get token decimals
        const decimals = await token.decimals();
        
        // Calculate required tokens
        const softCap = ethers.parseEther("0.01");
        const tokenAmount = ethers.parseUnits("300", "ether");
        const lpInterestRate = 51;
        
         console.log("Fairlanch tokens required:", ethers.formatUnits(tokenAmount, "ether"));
        
        // Calculate LP tokens
        const factory = await ethers.getContractAt("TrendPadIDOFairLaunchFactoryV2","0xb2b1b47Ca42D6aEB8810cfA28c555382d62Ae32C");
         const lpTokenAmount= await factory.getFairLaunchTokenAmount(tokenAmount,lpInterestRate,decimals);
        // Total tokens needed

        console.log("LP tokens required:", ethers.formatUnits(lpTokenAmount, "ether"));
        const totalTokensNeeded = tokenAmount+lpTokenAmount;
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
      //   const approveTx = await token.approve(
      //       "0xb2b1b47Ca42D6aEB8810cfA28c555382d62Ae32C", 
      //       approveAmount,{
      //  nonce:nonce+1,
    	// gasLimit: 5000000,  // Increase gas limit
    	// gasPrice: ethers.parseUnits("10", "gwei") 
    	// 	}
      //   );
      //   await approveTx.wait();
      //   console.log("Approved token transfer of", ethers.formatUnits(approveAmount, "ether"), "tokens");
      
        // Now create the IDO with 60% LP interest rate
      
        const saleInfo = {
          saleToken: "0xCB34f3Bb2ccaf5ef8aa21197c44Ed0973a362FF8",
          tokenAmount: ethers.parseUnits("300", "ether"),
          liquidityToken: lpTokenAmount,
          softCap: ethers.parseEther("0.01"),
          maxPay: ethers.parseEther("0.02"),
          lpPercent: 51, // ← Set to 60%
          affilation: false,
          isEnableWhitelist: false,
          isBuyBackEnabled:true,
          isVestingEnabled: false,
          metadataURL: "ipfs://your-metadata-url"

        };

        const timestamps = {
          startTimestamp: Math.floor(Date.now() / 1000) + 720,
          endTimestamp: Math.floor(Date.now() / 1000) + 1800,
          claimTimestamp: 0,
          unlockTimestamp: 180
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
        const tx = await factory.createFairLaunch(
          saleInfo,
          timestamps,
          dexInfo,
          VestingInfo,
          "0x880674380d2818dE6B0b642Ca4D995C20A51D7B3",
          0,
          2,
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
        //   console.log("Event not found. Check TrendPools array for the new pool.");
        //   const pools = await factory.getTrendPools();
        //   console.log("Latest pool:", pools[pools.length - 1]);
        // }
      }
    }
      
      main().catch(console.error);
