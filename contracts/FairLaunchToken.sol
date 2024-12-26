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

contract FairLaunchToken is Ownable,ReentrancyGuard{
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    struct SaleInfo{
        uint256 tokenAmount;
        uint256 softCap;
        uint256 maxPay;
        uint256 lpPercentage;
    }

    struct DexInfo {
        address router;
        address factory;
        address weth;
    }


    struct Timestamps{
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 unlockTimestamp;
    }
    struct UserInfo{
        uint256 debt;
        uint256 total;
        uint256 totalInvested;
    }
    ERC20 public  saleToken;
    ERC20 public payToken;
    uint256 public saleTokenDecimals;
    uint256 public payTokenDecimals;
     
     string public metadataUrl;
     address public feeWallet;
     uint public feePercent;
     bool public IsPoolCancel;

     SaleInfo public saleInfo;
     Timestamps public timestamps;
     DexInfo public dexInfo;
    ITrendLock public locker;

    uint256 public totalInvested;
    uint256 public tokensForDistribution;
    uint256 public distributedTokens;
     
    bool public distributed = false;

    mapping (address=> UserInfo) public userInfo;

    event TokenDebt(address indexed  holder,
   uint256 payAmount,
   uint tokenAmount 
    );
    event TokenWithdrawn(address indexed holder,uint256 amount);
    event PoolCancelled(uint timestamps);

 constructor(
    ERC20 _saleToken,
    ERC20 _payToken,
    SaleInfo memory _saleInfo,
    Timestamps memory _timestamps,
    DexInfo memory _dexInfo,
    address _lockerAddress,
    string memory _metaDataURL,
    address _feeWallet,
    uint _feePercent
     )Ownable(msg.sender){
     saleToken=_saleToken;
     saleTokenDecimals=_saleToken.decimals();
     payToken=_payToken;
     payTokenDecimals=payToken.decimals();
    dexInfo = _dexInfo;
    locker=ITrendLock(_lockerAddress);
    saleInfo=_saleInfo;
    feeWallet=_feeWallet;
    feePercent=_feePercent;

    setMetadataURL(_metaDataURL);
    setTimestamps(_timestamps);


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
        metadataUrl = _metadataURL;
    }

    function pay(uint256 _amount)  external{
        require(block.timestamp>=timestamps.startTimestamp," Sale Not Started yet");
        require(block.timestamp < timestamps.endTimestamp, "Ended");
        UserInfo storage user = userInfo[msg.sender];
        if(saleInfo.maxPay>0){
        require(_amount<=saleInfo.maxPay,"More than maxAmount");
        require(user.totalInvested.add(_amount) <= saleInfo.maxPay, "More then max amount");
        }
        totalInvested = totalInvested.add(_amount);
        user.totalInvested = user.totalInvested.add(_amount);
        user.debt = user.debt.add(_amount); 
        emit TokenDebt(msg.sender, _amount, _amount);
    }
     // calculate tokens on basis of userContribution 
    function getTokenPrice (uint _userContribution) public view returns (uint256){
      return _userContribution.mul(saleInfo.tokenAmount).div(totalInvested) ;
    }

     // calculate current tokens Rate  
    function CurrentTokenRate ()public view returns (uint256){
        uint256 scale =10**18;
        return saleInfo.tokenAmount.mul(scale).div(totalInvested);
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
        require(totalInvested >= saleInfo.softCap, "The IDO pool did not reach soft cap.");
        require(distributed,"Wait for Pool Finalize");
        UserInfo storage user = userInfo[_receiver];
        uint256 _amount = user.debt;
        require(_amount > 0 , "You do not have contributions"); 
        uint256 tokenAmount = getTokenPrice(_amount);
        user.debt=0;
        user.total=tokenAmount;
        distributedTokens = distributedTokens.add(_amount);
        saleToken.safeTransfer(_receiver, tokenAmount);
        emit TokenWithdrawn(_receiver,_amount);
    }

    function Finalize() external onlyOwner{
     require(block.timestamp > timestamps.endTimestamp, "The IDO pool has not ended.");
     require(totalInvested >= saleInfo.softCap, "The IDO pool did not reach soft cap.");
     require(!distributed, "Already distributed.");
     distributed = true;
     uint256 payTokenBalance=payToken.balanceOf(address(this));
     require(payTokenBalance==totalInvested,"payToken Balance Not Match");
     uint256 platformFee=payTokenBalance.mul(feePercent).div(10000);
     payTokenBalance=payTokenBalance.sub(platformFee);
     bool feeTransferSuccess=payToken.transfer(feeWallet, platformFee);
     require(feeTransferSuccess,"Platform fee transfer failed");
     uint256 balance = payToken.balanceOf(address(this));
     require(balance>0,'Not Enough Funds in Pool');
       
     if (saleInfo.lpPercentage > 0 ) {
            uint256 payTokenForLp = (balance * saleInfo.lpPercentage) / 100;
            uint256 payTokenWithdraw = balance - payTokenForLp;

            uint256 saleTokenAmount = getFairLaunchTokenAmount(saleInfo.tokenAmount,saleInfo.lpPercentage,saleTokenDecimals);

            // Add Liquidity Token
            IUniswapV2Router02 uniswapRouter = IUniswapV2Router02(dexInfo.router);
            saleToken.approve(address(uniswapRouter), saleTokenAmount);
             payToken.approve(address(uniswapRouter), payTokenForLp);

            (,, uint liquidity) = uniswapRouter.addLiquidity(
                address(saleToken),
                address(payToken),
                saleTokenAmount,
                payTokenForLp,
                0, // slippage is unavoidable
                0, // slippage is unavoidable
                address(this),
                block.timestamp + 360
            );
            // Lock LP Tokens
            address lpTokenAddress = IUniswapV2Factory(dexInfo.factory).getPair(
                address(saleToken),
                address(payToken)
            );

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
            } 

            // Withdraw rest Token
            bool transferSuccess = payToken.transfer(
                msg.sender,
                payTokenWithdraw
            );
            require(transferSuccess, "Transfer failed.");
        } else {
            bool transferSuccess = payToken.transfer(msg.sender, balance);
            require(transferSuccess, "Transfer failed.");
        }

    }

    function cancelSale() external onlyOwner {
    require(!IsPoolCancel, "Pool already canceled");
    require(block.timestamp < timestamps.endTimestamp, "Cannot cancel after the sale ends");
    IsPoolCancel = true;
    emit PoolCancelled(block.timestamp);
}

    function refundTokens() external onlyOwner {
        // require(block.timestamp > timestamps.endTimestamp, "The IDO pool has not ended.");
        // require(totalInvestedETH < finInfo.softCap, "The IDO pool has reach soft cap."); // this is for some times disble after checking proper 
        require(IsPoolCancel, "Pool is not canceled");
        uint256 balance = saleToken.balanceOf(address(this));
        require(balance > 0, "The IDO pool has not refund tokens.");
        saleToken.safeTransfer(msg.sender, balance);
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
// [1734507409,1734507509,1734507609]
// 0xdD870fA1b7C4700F2BD7f44238821C26f7392148
// 200000000000000000

// 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2
// 0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db
// 0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db
// 0x617F2E2fD72FD9D5503197092aC168c91465E7f2
// 0x17F6AD8Ef982297579C203069C1DbfFE4348c372
// 0x5c6B0f7Bf3E7ce046039Bd8FABdfD3f9F5021678
// 0x03C6FcED478cBbC9a4FAB34eF9f40767739D1Ff7