// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./ITrendLock.sol";
contract Fairlaunch is Ownable, ReentrancyGuard {
    using SafeERC20 for ERC20;
    using SafeMath for uint256;


     struct SaleInfo {
        uint256  tokenAmount;
        uint256 softCap;
        uint256 maxPay;
        uint256 lpPayPercent;
    }

    struct Timestamps {
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 unlockTimestamp;
    }

    struct DEXInfo {
        address router;
        address factory;
        address weth;
    }

     struct UserInfo {
        uint debt;
        uint total;
        uint totalInvestedETH;
    }
    ERC20 public saleToken;
    uint256  public decimals;
    string public metaDataURl;
    address public feeWallet;
    uint256 public feePercent;
    bool public IsPoolCancel;


    SaleInfo public saleInfo;
    Timestamps public timestamps;
    DEXInfo public dexInfo;
    ITrendLock public locker;
    
    uint256 public totalInvestedEth;
    uint256 public tokensForDistribution;
    uint256 public distributedTokens;

    bool public distributed=false;

    mapping (address=> UserInfo) public userInfo;

    event TokenDebt(address indexed holder,
    uint256 ethAmount,
    uint256 tokenAmount);

    event PoolCancelled(uint timestamps);
    event TokenWithdraw(address indexed holder,uint256 amount);

    constructor(
        ERC20 _saleTokenAddress,
        SaleInfo memory _saleInfo,
        Timestamps memory _timestamps,
        DEXInfo memory _dexInfo,
        address _lockerAddress,
        address _feeWallet,
        uint _feePercent
    )
    Ownable(msg.sender)
    {
        saleToken=_saleTokenAddress;
        decimals=saleToken.decimals();
        locker=ITrendLock(_lockerAddress);
        feeWallet=_feeWallet;
        feePercent=_feePercent;
        saleInfo=_saleInfo;
        setTimestamps(_timestamps);
        dexInfo=_dexInfo;
    }

      function setTimestamps(Timestamps memory _timestamps) internal {
        require(
            _timestamps.startTimestamp < _timestamps.endTimestamp,
            "Start timestamp must be less than finish timestamp"
        );
        require(
            _timestamps.endTimestamp > block.timestamp,
            "Finish timestamp must be more than current block"
        );

        timestamps = _timestamps;
    }

    function setMetadataURL(string memory _metadataURL) public{
        metaDataURl = _metadataURL;
    }

    function pay() payable external{
        require(block.timestamp>=timestamps.startTimestamp," Sale Not Started yet");
        require(block.timestamp < timestamps.endTimestamp, "Ended");
        UserInfo storage user = userInfo[msg.sender];
        if(saleInfo.maxPay>0){
        require(msg.value<=saleInfo.maxPay,"More than maxAmount");
        require(user.totalInvestedETH.add(msg.value) <= saleInfo.maxPay, "More then max amount");
        }
       totalInvestedEth = totalInvestedEth.add(msg.value);
       user.totalInvestedETH = user.totalInvestedETH.add(msg.value);
       user.debt = user.debt.add(msg.value); 
       emit TokenDebt(msg.sender, msg.value, msg.value);
    }

    // calculate tokens on basis of userContribution 
    function getTokenPrice (uint _userContribution) public view returns (uint256){
      return _userContribution.mul(saleInfo.tokenAmount).div(totalInvestedEth) ;
    }

    // calculate current tokens Rate  
    function CurrentTokenRate ()public view returns (uint256){
        uint256 scale =10**18;
        return saleInfo.tokenAmount.mul(scale).div(totalInvestedEth);
    }
    
    function claimFor(address _user) external {
     proccessClaim(_user);
    }

     function claim() external {//  user claim itself thier token 
        proccessClaim(msg.sender);
    }

    function proccessClaim(
        address _receiver
    )
    public 
     nonReentrant{
        require(block.timestamp > timestamps.endTimestamp, "The IDO pool has not ended.");
        require(totalInvestedEth >= saleInfo.softCap, "The IDO pool did not reach soft cap.");
        require(distributed,"Wait for Pool Finalize");
        UserInfo storage user = userInfo[_receiver];
        uint256 _amount = user.debt;
        require(_amount > 0 , "You do not have contributions"); 
        uint256 tokenAmount = getTokenPrice(_amount);
        user.debt=0;
        user.total=tokenAmount;
        distributedTokens = distributedTokens.add(_amount);
        saleToken.safeTransfer(_receiver, tokenAmount);
        emit TokenWithdraw(_receiver,_amount);
    }

    function Finalize() external payable  onlyOwner {
        require(block.timestamp > timestamps.endTimestamp, "The IDO pool has not ended.");
        require(totalInvestedEth >= saleInfo.softCap, "The IDO pool did not reach soft cap.");
        require(!distributed, "Already distributed.");
        distributed = true;
        uint256 contractBalance=address(this).balance;
        require(contractBalance==totalInvestedEth,"Contract blsnce Not Match");
        uint256 platformFee=contractBalance.mul(feePercent).div(10000);
        contractBalance=contractBalance.sub(platformFee);  
        (bool feeTransferSuccess, ) = feeWallet.call{value: platformFee}("");
        require(feeTransferSuccess, "Platform fee transfer failed");
        uint256 balance = address(this).balance;
        require(balance>0,'Not Enough Funds in Pool');

         if ( saleInfo.lpPayPercent > 0) {
          
            uint256 ethForLP = (balance * saleInfo.lpPayPercent)/100;
            uint256 ethWithdraw = balance - ethForLP;

            uint256 tokenAmount = getFairLaunchTokenAmount(saleInfo.tokenAmount,saleInfo.lpPayPercent,decimals );
           
            // Add Liquidity ETH
            IUniswapV2Router02 uniswapRouter = IUniswapV2Router02(dexInfo.router);
            saleToken.approve(address(uniswapRouter), tokenAmount);
            (,, uint liquidity) = uniswapRouter.addLiquidityETH{value: ethForLP}(
                address(saleToken),
                tokenAmount,
                0, // slippage is unavoidable
                0, // slippage is unavoidable
                address(this),
                block.timestamp + 360
            );

            // Lock LP Tokens
            (address lpTokenAddress) = IUniswapV2Factory(dexInfo.factory).getPair(address(saleToken), dexInfo.weth);

            ERC20 lpToken = ERC20(lpTokenAddress);

            if (timestamps.unlockTimestamp > block.timestamp) {
                lpToken.approve(address(locker), liquidity);
                locker.lock(
                    msg.sender,
                    lpTokenAddress,
                    true,
                    liquidity,
                    timestamps.unlockTimestamp,
                    string.concat(lpToken.symbol(), " tokens locker")
                );
            } else {
                lpToken.transfer(msg.sender, liquidity);
                // return msg.value along with eth to output if someone sent it wrong
                ethWithdraw += msg.value;
            }
            // Withdraw  restETH
            // (bool success ) = msg.sender.call{value: ethWithdraw}("");
            // require(success, "Transfer failed.");
        } else {
            (bool success, ) = msg.sender.call{value: balance}("");
            require(success, "Transfer failed.");
        }
        distributed = true;
    }

    function refundTokens() external onlyOwner {
        // require(block.timestamp > timestamps.endTimestamp, "The IDO pool has not ended.");
        // require(totalInvestedETH < finInfo.softCap, "The IDO pool has reach soft cap."); // this is for some times disble after checking proper 
        require(IsPoolCancel, "Pool is not canceled");
        uint256 balance = saleToken.balanceOf(address(this));
        require(balance > 0, "The IDO pool has not refund tokens.");
        saleToken.safeTransfer(msg.sender, balance);
    }
    
    function cancelSale() external onlyOwner {
        require(!IsPoolCancel, "Pool already canceled");
        require(block.timestamp < timestamps.endTimestamp, "Cannot cancel after the sale ends");
        IsPoolCancel = true;
        emit PoolCancelled(block.timestamp);
}

  function getFairLaunchTokenAmount(
    uint256 _amount, 
    uint lpPercent, 
    uint256 _decimals
) public view returns (uint256) {
    uint256 _ethAmount = 1 ether; // 1 ETH in wei
    uint256 fee = (_ethAmount * feePercent) / 100; // Calculate fee
    uint256 adjustedEthAmount = _ethAmount - fee; // Adjust ETH amount after fee
    uint256 lpAdjusted = (adjustedEthAmount * lpPercent) / 100; // Adjust by lpPercent
    uint256 finalAmount = (lpAdjusted * _amount) / (10 ** _decimals); // Final amount
    return finalAmount;
}
  }
  
// [1000000000000000000000,100000000000000000,0,51]
// [1734494244,1734494344,1734494444]
// 0xdD870fA1b7C4700F2BD7f44238821C26f7392148
// 4