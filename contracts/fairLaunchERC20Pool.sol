// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

    import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
    import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
    import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
    import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
    import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
    import "./IUniswapV2Router02.sol";
    import "./IUniswapV2Factory.sol"; 
    import "./IUniswapV2Pair.sol";

    interface ITrendLock {                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        
        function lock(
            address _withdrawer,
            address _token,
            bool _isLpToken,
            uint256 _amount,
            uint256 _unlockTimestamp,
            string calldata _description
        ) external;
    }

    interface IBuyBackManager {
        function finalizeBuyBackConfig(
            address _pool
            ,uint256 _amount
        ) payable external;

    }   
contract TrendFairlaunchERC20PoolV2 is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable{
    using SafeERC20 for ERC20;

    struct SaleInfo {
        address currency; // Currency used for contributions (e.g., ETH)
        address saleToken;
        uint256 tokenAmount;
        uint256 liquidityToken;
        uint256 softCap;
        uint256 maxPay;
        uint256 lpPercent;
        bool isAffiliatationEnabled;
        bool isEnableWhitelist;
        bool isBuyBackEnabled;
        bool isVestingEnabled;
    }
    
    struct Timestamps {
        uint256 startTimestamp;  
        uint256 endTimestamp;    
        uint256 claimTimestamp;  
        uint256 unlockTime; 
    }

    struct VestingInfo {
       uint8 TGEPercent; // Percentage of tokens released at TGE
       uint256 cycleTime;
       uint8 releasePercent;
       uint256 startTime;
    }
    struct DEXInfo {
        address router;
        address factory;
        address weth;
    }

    struct UserInfo {
        uint debt;
        uint claimed;
        uint totalInvested;
        bool isRefunded; 
    }

    struct AffiliateInfo {             
     uint8 poolRefCount;            // Total number of users referred
     uint8 RewardPercentage;// Current reward % based on referrals
     uint256 currentReward;           // Current reward user can claim
     uint256 totalReferredAmount; // Total amount referred by user
     uint256 totalRewardAmount;    
}

  struct BuyBackInfo{
    uint8 buybackPercentage;
    address buyBackMangerAddrress;
  }

 // --------------------------------------------------------------------------------
    // Public state
    // --------------------------------------------------------------------------------

    uint8 public formateUnit;
    address public feeWallet;
    uint256 public feePercent;
    bool   public isPoolCancelled;
     
    SaleInfo public saleInfo;
    Timestamps public timestamps;
    DEXInfo public dexInfo;
    VestingInfo public vestingInfo;
    AffiliateInfo public affiliateInfo;
    BuyBackInfo public buyBackInfo;
    ITrendLock public locker;
    
    uint256 public totalInvested;
    uint256 public distributedTokens;
    address[] public participants;
    address[] public sponeserAddress;
    address[] public whitelistList;
    bool public distributed;

    enum SaleStatus {
    Cancelled,
    Upcoming,
    Live,
    Ended
   }

//  mapping
    mapping(address => bool) public whitelistedAddresses;
    mapping(address => UserInfo) public userInfo;
    mapping(address => uint256) public sponsorReferralSum;
    mapping (address=>uint256) public  sponserReward;
    mapping(address => bool) public sponsorClaimed;
    
    event TokensDebt(address indexed holder, uint256 currencyAmount);
    event PoolCancelled(uint256 timestamp);
    event TimestampsUpdated(uint256 startTimestamp, uint256 endTimestamp);
    event TokensWithdrawn(address indexed holder, uint256 amount);
    event WhitelistUpdated(address indexed user, bool status);
    event SponsorSet(address indexed user, address indexed sponsor);
    event SponsorRewardClaimed(address indexed sponsor, uint256 amount);
    event EndTimeUpdated(uint256 endTimestamp);
    event ContributionRefunded(address indexed user, uint256 amount);
    event PoolFinalized(address indexed pool, uint256 timestamp);
    event TokensRefunded(address indexed user, uint256 amount);
    event SaleTypeChanged(bool status);
    event AffiliateUpdated(bool enabled, uint8 rate);
    event claimTimeUpdated(uint256 claimTimestamp);
    event VestingUpdated(
        uint8 TGEPercent,
        uint256 cycleTime,
        uint8 releasePercent,
        uint256 startTime
    );
    event BuyBackUpdated(uint8 buybackPercentage, address buyBackMangerAddrress);

    function initialize(
            SaleInfo memory _saleInfo,
            Timestamps memory _timestamps,
            DEXInfo memory _dexInfo,
            address _locker,
            address _feeWallet,
            uint256 _feePercent
        ) public initializer {
            __Ownable_init(msg.sender);
            __ReentrancyGuard_init();
            timestamps = _timestamps;
            saleInfo = _saleInfo;
            locker = ITrendLock(_locker);
            feeWallet = _feeWallet;
            feePercent = _feePercent;
             formateUnit= ERC20(_saleInfo.currency).decimals();
            if(_saleInfo.lpPercent>0){// 
            dexInfo = _dexInfo;
        }
        }


function contribute(address _sponser,uint256 _amount)  external {
        require(getSaleStatus() == SaleStatus.Live, "Sale Is Not active");

        if (saleInfo.isEnableWhitelist) {
            require(whitelistedAddresses[msg.sender], "Your Not whitelisted");
        }

       ERC20(saleInfo.currency).safeTransferFrom(msg.sender, address(this), _amount);

        UserInfo storage user = userInfo[msg.sender];

        // Only check max contribution if maxPay is set (not zero)
        if (saleInfo.maxPay > 0) {
            require(_amount <= saleInfo.maxPay, "Exceeds your Max Pay");
            require(user.totalInvested + _amount <= saleInfo.maxPay, "Exceeds your Max Pay");
        }
        totalInvested = totalInvested + _amount;
        user.totalInvested = user.totalInvested + _amount;
        user.debt=user.debt +_amount;
        // Track participants if first time
        if (user.totalInvested == _amount) {
            participants.push(msg.sender);
        }

        // Affiliate logic (ETH)
        // -------------------------
        if (saleInfo.isAffiliatationEnabled) {
        _handleAffiliate(_sponser, _amount); 
        }
          emit TokensDebt(msg.sender, _amount);
    }
       /**
        * @notice Sponsor claims their ETH affiliate reward after finalize.
        */

function claimSponsorReward() external nonReentrant {
    require(saleInfo.isAffiliatationEnabled, "Affiliate disabled");
    require(distributed, "Pool not finalized");
    require(!sponsorClaimed[msg.sender], "Already claimed");
    require(sponserReward[msg.sender] > 0, "Nothing to claim");

    uint256 reward = sponserReward[msg.sender];
    uint256 fee = reward * (feePercent) / (100);
    uint256 netReward = reward-fee;

    sponsorClaimed[msg.sender] = true;
    ERC20(saleInfo.currency).safeTransfer(msg.sender, fee); // Transfer fee to fee wallet
    emit SponsorRewardClaimed(msg.sender, netReward);
}

// After sale cancel user can claim their contribution
function withdrawContribution()external nonReentrant {
require(isPoolCancelled || !isSoftcapReached(), "Refund not allowed: sale successful and not cancelled");
        UserInfo storage user = userInfo[msg.sender];
        require(!user.isRefunded, "Already refunded");
        uint256 amount = user.totalInvested;

        require(amount > 0, "No investment");
        // reset user
        user.debt             = 0;
        user.totalInvested    = 0;
        user.isRefunded = true; // Mark as refunded
        ERC20(saleInfo.currency).safeTransfer(msg.sender, amount);
        emit ContributionRefunded(msg.sender, amount);
}

function claim() external {
        proccessClaim(msg.sender);
}

// Calculate tokens on basis of userContribution 
function getTokenPrice(uint256 _userContribution) public view returns (uint256) {
    return totalInvested > 0?_userContribution * (saleInfo.tokenAmount) / (totalInvested): saleInfo.tokenAmount;    
}

// Calculate current tokens Rate  
function currentTokenRate() public view returns (uint256) {
    if (totalInvested == 0) return 0;
    return ((saleInfo.tokenAmount) * (10 ** formateUnit)) / (totalInvested);
}


// public Function 

function getSaleType() external view returns (string memory) {
    return saleInfo.isEnableWhitelist ? "Whitelist" : "Public";
}

function getAllParticipant () external view returns(address [] memory){
    return  participants;
}

function getTotalParticipantCount() external view returns(uint256){
    return participants.length;
}

function getClaimableSponsorReward(address _sponsor) external view returns (uint256) {
    if (sponsorClaimed[_sponsor]) return 0;
    uint256 raw = sponserReward[_sponsor];
    uint256 fee = (raw * feePercent)/100;
    return raw-fee;
}

// Function to calculate claimable tokens
function getClaimableTokenAmount(address _user) external view returns (uint256) { 
    UserInfo storage user = userInfo[_user];
    
    // If no contributions or already fully claimed, return 0
    if (user.debt == 0) {
        return 0;
    }
    
    uint256 totalTokenAmount = getTokenPrice(user.debt);
    
    // If vesting is not enabled, check if already claimed
    if (!saleInfo.isVestingEnabled || vestingInfo.startTime == 0) {
        return user.claimed > 0 ? 0 : totalTokenAmount;
    }
    
    // Get vested amount
    uint256 vestedAmount = getVestedAmount(totalTokenAmount);
    
    // If nothing has vested or everything vested has been claimed
    if (vestedAmount <= user.claimed) {
        return 0;
    }
    
    // Return unclaimed vested tokens
    return vestedAmount - user.claimed;
}

   // Calculate how much of the total allocation is vested (available) at the current time
function getVestedAmount(uint256 _totalAmount) public view returns (uint256) {
    // If vesting hasn't started yet, nothing is vested
    if (block.timestamp < vestingInfo.startTime) {
        return 0;
    }
    
    // Calculate TGE portion
    uint256 tgePortion = _totalAmount * (vestingInfo.TGEPercent)/(100);
    uint256 vestedAmount = tgePortion;
    
    // Calculate additional vested amount based on cycles elapsed
    uint256 timeSinceTGE = block.timestamp-(vestingInfo.startTime);
    
    // Only calculate cycle-based vesting if necessary parameters are set
    if (timeSinceTGE > 0 && vestingInfo.cycleTime > 0 && vestingInfo.releasePercent > 0) {
        uint256 cyclesElapsed = timeSinceTGE / (vestingInfo.cycleTime);
        
        // Calculate amount vested per cycle
        uint256 remainingAfterTGE = _totalAmount-(tgePortion);
        uint256 cycleUnlockPerCycle = remainingAfterTGE * (vestingInfo.releasePercent)/(100);
        
        // Calculate total amount unlocked through cycles
        uint256 totalCycleUnlock = cycleUnlockPerCycle*(cyclesElapsed);
        
        // Add cycle unlocks to TGE portion
        vestedAmount = vestedAmount+ totalCycleUnlock;

        // Cap at total allocation
        if (vestedAmount > _totalAmount) {
            vestedAmount = _totalAmount;
        }
    }

    return vestedAmount;
}


function isPoolUser(address _user) external view returns ( bool){
    UserInfo storage user = userInfo[_user];
    return user.totalInvested>0?true :false;
}

function getClaimedTokenAmount (address _user) external view returns (uint256){
    UserInfo storage user = userInfo[_user];
    return  user.claimed;
}

function getUserInvesmentAmount(address _user) external view returns (uint256){
    UserInfo storage user = userInfo[_user];
    return user.totalInvested;
}
    
function getSponserAddress() external view  returns(address[] memory){
    return sponeserAddress;
}

function getSponserReferalAmount(address _sponser) external view returns(uint256){
    return sponsorReferralSum[_sponser];
}

function getSponserRewardAmount(address _sponser) external  view  returns(uint256){
        if (sponsorClaimed[_sponser]) return 0;
        uint256 raw = sponserReward[_sponser];
        uint256 fee = (raw * feePercent)/100;
        return raw -fee;
}

function getIsSponsorClaimed(address _sponser) external view returns (bool) {
        return sponsorClaimed[_sponser];
}

function getSaleInfo() external  view returns (SaleInfo memory){
 return saleInfo;
}

function getTimeStampInfo() external view returns(Timestamps memory){
return timestamps;
} 

function getAffilateInfo() external  view returns(AffiliateInfo memory){
return affiliateInfo;
}

function getTotalInvested() external  view returns(uint256){
return totalInvested;
}

function getVestingInfo() external view returns (VestingInfo memory){
    return vestingInfo;
}

function isPoolFinalize() external view  returns (bool){
        return distributed;
}

function getBuyBackPercentage() public view returns (uint8) {
    return saleInfo.isBuyBackEnabled ? buyBackInfo.buybackPercentage : 0;
} 

function getFairLaunchTokenAmount(
            uint256 _amount, 
            uint lpPercent,
            uint8 decimals
        ) internal view returns (uint256) {
            uint256 _ethAmount = 1 * 10** decimals; // 1 ETH in wei
            uint256 fee = (_ethAmount * feePercent) / 100; // Calculate fee
            uint256 adjustedEthAmount = _ethAmount - fee; // Adjust ETH amount after fee
            uint256 lpAdjusted = (adjustedEthAmount * lpPercent) / 100; // Adjust by lpPercent
            uint256 finalAmount = (lpAdjusted * _amount) / (10 ** decimals); // Final amount
            return finalAmount;
}
 
       // Status checks
function getSaleStatus() public view returns (SaleStatus) {
    if (isPoolCancelled) {
        return SaleStatus.Cancelled;
    }
    if (block.timestamp < timestamps.startTimestamp) {
        return SaleStatus.Upcoming;
    }
    if (block.timestamp >= timestamps.endTimestamp) {
        return SaleStatus.Ended;
    }
    // This block only runs if sale is ongoing
    if (
        block.timestamp >= timestamps.startTimestamp &&
        block.timestamp < timestamps.endTimestamp
    ) {
            return SaleStatus.Live;
    }
    return SaleStatus.Ended; // Fallback
}

function isClaimTimeSet() external view returns (bool) {
    return timestamps.claimTimestamp > 0;
}

function isSoftcapReached() public view returns (bool) {
    return totalInvested >= saleInfo.softCap;
}

function isUserRefunded(address _user) external view returns (bool) {
    UserInfo storage user = userInfo[_user];
    return user.isRefunded;
}

function getAffilationPercentage() external view returns (uint8) {
    return saleInfo.isAffiliatationEnabled ? affiliateInfo.RewardPercentage : 0;
}

// Internal Function
 /**
 * @dev Process token claims, with vesting support
 * @param _receiver Address receiving the tokens
 */
function proccessClaim(address _receiver) public nonReentrant {
    require(!isPoolCancelled, "Pool is cancelled");
    require(distributed, "Wait for Pool Finalize");
    require(block.timestamp >= timestamps.claimTimestamp, "Claim not started");
    require(totalInvested >= saleInfo.softCap, "The IDO pool did not reach soft cap.");        
    
    UserInfo storage user = userInfo[_receiver];
    uint256 debt = user.debt;
    require(debt > 0, "No contributions found");
    
    uint256 totalTokenAmount = getTokenPrice(debt);
    uint256 availableToClaimNow;
    
    // If vesting is not enabled, claim all tokens at once
    if (!saleInfo.isVestingEnabled || vestingInfo.startTime == 0) {
        // Check if already claimed
        require(user.claimed == 0, "Already claimed");
        
        // Claim full amount
        availableToClaimNow = totalTokenAmount;
        user.debt = 0;
    } else {
        // Vesting is enabled - calculate available amount
        uint256 vestedAmount = getVestedAmount(totalTokenAmount);
        
        // If nothing has vested yet
        require(vestedAmount > 0, "No tokens vested yet");
        
        // Calculate unclaimed vested tokens
        uint256 unclaimedVested = vestedAmount > user.claimed ? 
                                  vestedAmount - user.claimed : 0;
        
        require(unclaimedVested > 0, "No new tokens available to claim");
        
        availableToClaimNow = unclaimedVested;
        
        // If all tokens are claimed, clear the debt
        if (vestedAmount >= totalTokenAmount) {
            user.debt = 0;
        }
    }
    
    // Update claimed amount
    user.claimed = user.claimed + availableToClaimNow;
    
    // Update global tracking
    distributedTokens = distributedTokens + availableToClaimNow;
    
    // Transfer tokens
    ERC20(saleInfo.saleToken).safeTransfer(_receiver, availableToClaimNow);
    
    emit TokensWithdrawn(_receiver, availableToClaimNow);
}
   
   function _handleAffiliate(address _sponsor, uint256 amount) internal {
    if (_sponsor != address(0) && _sponsor != msg.sender) {
        if (sponsorReferralSum[_sponsor] == 0) {
            sponeserAddress.push(_sponsor);
            affiliateInfo.poolRefCount++;
        }
        sponsorReferralSum[_sponsor] += amount;
        uint256 reward = (uint256(affiliateInfo.RewardPercentage) * (amount))/(100);
        sponserReward[_sponsor] += reward;
        affiliateInfo.totalReferredAmount += amount;
        affiliateInfo.currentReward += reward;
    }
}
// admin control Function 
function finalize() external payable onlyOwner {
    require(!distributed, "Already finalized");
    require(!isPoolCancelled, "Pool is cancelled");
    require(block.timestamp > timestamps.endTimestamp, "The IDO pool has not ended.");
    require(totalInvested >= saleInfo.softCap, "The IDO pool did not reach soft cap.");
    require(timestamps.claimTimestamp > 0, "First set Claim Time");

    uint256 contributionRemain = totalInvested;

    // 1. Deduct platform fee
    uint256 platformFee = contributionRemain * (feePercent) / (100);
    contributionRemain = contributionRemain - platformFee;

    ERC20(saleInfo.currency).safeTransfer(feeWallet, platformFee);

    // 2. If AutoListing Enabled
    if (saleInfo.lpPercent > 0) {
        // calculate ETH for LP
        require(!doesLiquidityExist(dexInfo.factory, saleInfo.saleToken, dexInfo.weth),"Token Liquidity already exists it will not Finalize");
        uint256 CurrencyForLp = contributionRemain * saleInfo.lpPercent / (100);
        contributionRemain = contributionRemain - CurrencyForLp;

        uint256 tokenForLp = getFairLaunchTokenAmount(
            saleInfo.tokenAmount,
            saleInfo.lpPercent,
            formateUnit
        );
        // Add Liquidity ETH
        IUniswapV2Router02 uniswapRouter = IUniswapV2Router02(dexInfo.router);
        ERC20(saleInfo.saleToken).approve(address(uniswapRouter), tokenForLp);
        ERC20(saleInfo.currency).approve(address(uniswapRouter), CurrencyForLp);
        // Add liquidity to Uniswap
        (,, uint256 liquidity) = uniswapRouter.addLiquidity(
            address(saleInfo.currency),
            address(saleInfo.saleToken),
            CurrencyForLp,
            tokenForLp,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp + (360)
        );

        // Lock LP Tokens
        address lpTokenAddress = IUniswapV2Factory(dexInfo.factory).getPair(address(saleInfo.saleToken), address(saleInfo.currency));
        ERC20 lpToken = ERC20(lpTokenAddress);

        if (timestamps.unlockTime > 0) {
            lpToken.approve(address(locker), liquidity);
            locker.lock(
                msg.sender,
                lpTokenAddress,
                true,
                liquidity,
                timestamps.unlockTime +block.timestamp,
                string.concat(lpToken.symbol(), " Tokens Locker")
            );
        } else {
            lpToken.transfer(msg.sender, liquidity);
        }
    }
    
    // 3. Handle Affiliation logic 
    if (saleInfo.isAffiliatationEnabled) {
        uint256 affilationReward = affiliateInfo.currentReward -(
            (affiliateInfo.currentReward * feePercent)/(100)
        );
        affiliateInfo.totalRewardAmount = affilationReward;
        contributionRemain = contributionRemain - affilationReward;
    }

    // 4. Handle BuyBack logic
    if (saleInfo.isBuyBackEnabled) {
        uint256 buybackAmount = (totalInvested * buyBackInfo.buybackPercentage)/(100);
        buybackAmount = buybackAmount-(buybackAmount*(feePercent)/(100));
        contributionRemain = contributionRemain - buybackAmount;
        IBuyBackManager(buyBackInfo.buyBackMangerAddrress).finalizeBuyBackConfig{value: 0}(address(this),buybackAmount);
        // Transfer buyback amount to BuyBackManager
        ERC20(saleInfo.currency).safeTransfer(
            buyBackInfo.buyBackMangerAddrress,
            buybackAmount
        );
    }

    // 5. Transfer remaining funds to admin
    ERC20(saleInfo.currency).safeTransfer(
        msg.sender,
        contributionRemain
    );

    distributed = true;
    emit PoolFinalized(address(this), block.timestamp);
}
       /**
     * @notice Cancel sale before finalise Pool. Allows refunds.
     */
    function cancelSale() external onlyOwner {
        require(!isPoolCancelled, "Sale already cancelled");
        require(!distributed, "Sale cannot be cancelled after finalization");
        isPoolCancelled = true;
        emit PoolCancelled(block.timestamp);
    }

    /**
     * @notice Withdraw tokens back to owner if canceled and soft cap not met
     */

function RefundToContributor() external onlyOwner {
            require(isPoolCancelled, "Pool is not canceled");
            for (uint256 i = 0; i < participants.length; i++) {
                UserInfo storage user = userInfo[participants[i]];
                if (user.totalInvested > 0 && !user.isRefunded) {
                    uint256 amount = user.totalInvested;
                    user.totalInvested = 0; // Reset investment
                    user.debt = 0; // Reset debt
                    user.isRefunded = true; // Mark as refunded
                     ERC20(saleInfo.currency).safeTransfer(participants[i], amount);
                }
            }
}

     function refundTokens() external onlyOwner {
            require(isPoolCancelled, "Pool is not canceled");
            uint256 balance =ERC20(saleInfo.saleToken).balanceOf(address(this));
            require(balance > 0, "The IDO pool has not refund tokens.");
            ERC20(saleInfo.saleToken).safeTransfer(msg.sender, balance);
            emit TokensRefunded(msg.sender, balance);
        }

     /**
     * @notice Distribute purchased tokens in batch by admin
     */
    function distributeTokens() external onlyOwner {
        for (uint256 i = 0; i <participants.length;i++) {
                UserInfo storage user = userInfo[participants[i]];
                if(user.claimed==0){
                proccessClaim(participants[i]);
            }
        }
     }
     /**
     * @notice Add multiple addresses to the whitelist
     */
    function addBatchToWhitelist(address[] calldata _addresses) external onlyOwner {
            for (uint256 i = 0; i < _addresses.length; i++) {
            address addr = _addresses[i];
            if (!whitelistedAddresses[addr]) {
                whitelistedAddresses[addr] = true;
                whitelistList.push(addr);
                emit WhitelistUpdated(addr, true);
            }
        }
}

        /**
        * @notice Remove multiple addresses from the whitelist
        */
  function removeAllWhitelist() external onlyOwner {
            if (whitelistList.length == 0) return;

            for (uint256 i = 0; i < whitelistList.length; i++) {
                address addr = whitelistList[i];
                if (whitelistedAddresses[addr]) {
                    whitelistedAddresses[addr] = false;
                    emit WhitelistUpdated(addr, false);
                }
            }
            delete whitelistList; // 🧹 Clean up
}


        /**
     * @notice Enable or disable whitelist and public 
     */
function whitelistEnabled() external onlyOwner {
       require(!distributed, "Sale cannot be Enable WhiteListing after finalization");
       require(!saleInfo.isEnableWhitelist,"Sale Already WhiteListed");
       require(block.timestamp <= timestamps.endTimestamp, "Cannot change whitelist settings after sale Ends"); 
       saleInfo.isEnableWhitelist=true;
       emit SaleTypeChanged(true);
    }


function publicSaleEanble() external onlyOwner{
    require(!distributed, "cannot be Enable public  Sale after finalization");   
    require(block.timestamp<=timestamps.endTimestamp,"sale is ended can't update public");
    require(saleInfo.isEnableWhitelist,"Sale Already Public");
    saleInfo.isEnableWhitelist=false;
    emit SaleTypeChanged(false);
}


    /**
     * @notice Configure affiliate parameters (enabled & rate)
     * @param _enabled True if affiliate logic is active
     * @param _rate In basis points, e.g. 500 = 5%
     */

function enableAffilate(bool _enabled, uint8 _rate) external onlyOwner {
    require(
        getSaleStatus() == SaleStatus.Upcoming || 
        getSaleStatus() == SaleStatus.Live,
        "Affiliation Can only enable before sale end"
    );
    require(_rate <= 5, "Affiliation rate max is 5%");
    
    saleInfo.isAffiliatationEnabled = _enabled;
    
    // Only update rate if enabling or rate is changing
    if (_enabled || affiliateInfo.RewardPercentage != _rate) {
        affiliateInfo.RewardPercentage = _rate;
    }
    emit AffiliateUpdated(_enabled, _rate);
}

function setVesting(VestingInfo memory _vestingInfo) external {
    require(_vestingInfo.TGEPercent>0 && _vestingInfo.TGEPercent<=100, "TGE% must be > 0 and <= 100");
    require(_vestingInfo.releasePercent>0 && _vestingInfo.releasePercent<=100, "Release% must be > 0 and <= 100");
    require(_vestingInfo.releasePercent+(_vestingInfo.TGEPercent)<=100, "TGE% + Release% must be <= 100");
    require(_vestingInfo.cycleTime>0, "Cycle time must be > 0");
    _vestingInfo.startTime=0;
    vestingInfo=_vestingInfo;
    emit VestingUpdated(
        _vestingInfo.TGEPercent,
        _vestingInfo.cycleTime,
        _vestingInfo.releasePercent,
        _vestingInfo.startTime
    );
}

function setBuyBack(BuyBackInfo memory _buyBackInfo) external {
    require(_buyBackInfo.buybackPercentage>0,"Buy Back Percentage More than zero");
    require(_buyBackInfo.buyBackMangerAddrress!=address(0),"Buyback manager address not set");
    buyBackInfo=_buyBackInfo;
    emit BuyBackUpdated(
        _buyBackInfo.buybackPercentage,
        _buyBackInfo.buyBackMangerAddrress
    );
}

function setPoolEndTime(uint256 _endTimestamp) external onlyOwner {
        // Make sure the sale has not already ended
        require(
            block.timestamp < timestamps.endTimestamp,
            "Cannot update end time after the sale has ended."
        );

        require(
            _endTimestamp >= block.timestamp,
            "End time must be in the future or Now."
        );

        // Update the end timestamp
        timestamps.endTimestamp = _endTimestamp;

        // Emit an event for transparency
        emit EndTimeUpdated(_endTimestamp);
}

function setEndAndStartTime(
        uint256 _newStartTime,
        uint256 _newEndTime
    ) external onlyOwner {
        require(
            block.timestamp <= timestamps.startTimestamp,
            "Cannot update time after the sale has started."
        );

        require(
            _newStartTime < _newEndTime,
            "Start time must be less than end time."
        );
        require(
            _newStartTime > block.timestamp,
            "New start time must be in the future."
        );

        timestamps.startTimestamp = _newStartTime;
        timestamps.endTimestamp = _newEndTime;

        emit TimestampsUpdated(_newStartTime, _newEndTime);
}

function setClaimTime(uint256 _claimTimestamp) external onlyOwner {
        require(block.timestamp <=_claimTimestamp , "Claim time must be in the future or now");
        timestamps.claimTimestamp = _claimTimestamp;
        emit claimTimeUpdated(_claimTimestamp);
} 

function doesLiquidityExist(
    address factory,
    address tokenA,
    address tokenB
) public view returns (bool) {
    address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
    if (pair == address(0)) {
        return false; // Pair does not exist
    }
    (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pair).getReserves();
    return reserve0 > 0 && reserve1 > 0;
}

}
