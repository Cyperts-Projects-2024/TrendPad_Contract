// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
// import "./ITrendLock.sol";
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

    contract TrendPool is Initializable,OwnableUpgradeable, ReentrancyGuardUpgradeable {
        using SafeERC20 for ERC20;

        // --------------------------------------------------------------------------------
        // Structures
        // --------------------------------------------------------------------------------

            struct SaleInfo {
                address rewardToken;
                uint256 presaleToken;
                uint256 liquidityToken;
                uint256 tokenPrice;    // Price per token in WEI
                uint256 softCap;       // Min ETH required
                uint256 hardCap;       // Max ETH raised
                uint256 minEthPayment; // Min contribution
                uint256 maxEthPayment; // Max contribution
                uint256 listingPrice;  // (Optional) listing price in WEI
                uint256 lpInterestRate;// (Optional) % of raised ETH for LP
                bool  burnType;
                string metadataURL;
                bool affiliation; 
                bool isEnableWhiteList ;    // (Unused flag; we do actual affiliate logic below)
            }

        struct Timestamps {
            uint256 startTimestamp;  
            uint256 endTimestamp;    
            uint256 claimTimestamp;  
            uint256 unlockTime; 
        }

        struct DEXInfo {
            address router;
            address factory;
            address weth;
        }

        struct UserInfo {
            uint256 debt;            
            uint256 claimed;           
            uint256 totalInvestedETH;
        }

    struct AffiliateInfo {             
        uint8 poolRefCount;            // Total number of users referred
        uint8 realTimeRewardPercentage;// Current reward % based on referrals
        uint256 currentReward;           // Current reward user can claim
        uint256 maxReward;               // Max reward user can earn
        uint256 totalReferredAmount; // Total amount referred by user
        uint256 totalRewardAmount;    
    }
        // --------------------------------------------------------------------------------
        // Public state
        // --------------------------------------------------------------------------------

        uint256  public tokenDecimals;
        address  public feeWallet;
        uint8  public feePercent;       // fee in basis points
        bool     public isPoolCancelled;
        SaleInfo   public saleInfo;
        Timestamps public timestamps;
        DEXInfo    public dexInfo;
        AffiliateInfo public affiliateInfo;
        ITrendLock public locker;
        uint256 public totalInvestedETH;    // total ETH raised
        uint256 public tokensForDistribution;
        uint256 public distributedTokens; 
        bool  public distributed;
        enum SaleStatus {
        Cancelled,
        Upcoming,
        Live,
        Filled,
        Ended
    }
        // Whitelist
        mapping(address => bool) public whitelistedAddresses;
        address[] public participants;
        address[] public sponeserAddress;
        address[] public whitelistList;
        mapping(address => UserInfo) public userInfo;
        mapping(address => uint256) public sponsorReferralSum;
        mapping (address=>uint256) public  sponserReward;
        mapping(address => bool) public sponsorClaimed;

        // --------------------------------------------------------------------------------
        // Events
        // --------------------------------------------------------------------------------
        event TokensDebt(address indexed holder, uint256 ethAmount, uint256 tokenForLp);
        event PoolCancelled(uint256 timestamp);
        event TimestampsUpdated(uint256 startTimestamp, uint256 endTimestamp);
        event TokensWithdrawn(address indexed holder, uint256 amount);
        event WhitelistUpdated(address indexed user, bool status);
        // Affiliate-specific events
        event SponsorSet(address indexed user, address indexed sponsor);
        event SponsorRewardClaimed(address indexed sponsor, uint256 amount);
        // --------------------------------------------------------------------------------
        // Constructor
        // --------------------------------------------------------------------------------

        function initialize(
            SaleInfo memory _saleInfo,
            Timestamps memory _timestamps,
            DEXInfo memory _dexInfo,
            address _locker,
            address _feeWallet,
            uint8 _feePercent,
            uint8 _affiliateRate
        ) public initializer {
            __Ownable_init(msg.sender);
            __ReentrancyGuard_init();
            require(
                _timestamps.startTimestamp < _timestamps.endTimestamp,
                "Start < End required"
            );
            require(
                _timestamps.endTimestamp > block.timestamp,
                "End must be > now"
            );
    require(
        _timestamps.unlockTime == 0 || _timestamps.unlockTime >= 180,
        "Unlock time must be >= 3 mins or 0 (no lock)"
    );
            timestamps = _timestamps;
            require(_saleInfo.lpInterestRate >= 51 || _saleInfo.lpInterestRate==0, "LP% must be >= 51%");
            require(
                _saleInfo.softCap <= _saleInfo.hardCap &&
                (_saleInfo.hardCap * 25) / 100 <= _saleInfo.softCap,
                "SoftCap must be >= 25% of HardCap"
            );
            saleInfo = _saleInfo;
            dexInfo = _dexInfo;
            locker = ITrendLock(_locker);
            feeWallet = _feeWallet;
            feePercent = _feePercent;
            tokenDecimals = ERC20(saleInfo.rewardToken).decimals();
            if(_saleInfo.affiliation){
                affiliateInfo.realTimeRewardPercentage=_affiliateRate;
                affiliateInfo.maxReward=(_saleInfo.hardCap*_affiliateRate)/100;
            }
        }
        // --------------------------------------------------------------------------------
        // Public user functions
        // --------------------------------------------------------------------------------
    
        function contribute(address _sponsor) external payable nonReentrant {
            require(getSaleStatus() == SaleStatus.Live, "Sale Is Not active");
            require(msg.value >= saleInfo.minEthPayment||msg.value==(saleInfo.hardCap - totalInvestedETH), "Below min");
            require(msg.value <= saleInfo.maxEthPayment, "contribution  Above maxAmount");
            require(totalInvestedETH + msg.value <= saleInfo.hardCap, "Over hard cap");
            // Whitelist check
            if (saleInfo.isEnableWhiteList) {
                require(whitelistedAddresses[msg.sender], "Your Not whitelisted");
            }
            // Update user info
            UserInfo storage user = userInfo[msg.sender];
            require(user.totalInvestedETH + msg.value <= saleInfo.maxEthPayment, "Exceed personal max");
            user.totalInvestedETH += msg.value;
            // Calculate tokens owed
            uint256 tokenAmount = _getTokenAmount(msg.value, saleInfo.tokenPrice);
            user.debt  += tokenAmount;
            // Update global totals
            totalInvestedETH      += msg.value;
            tokensForDistribution += tokenAmount;
            // track participants if first time
            if (user.totalInvestedETH == msg.value) {
                participants.push(msg.sender);
            }

            // -------------------------
            // Affiliate logic (ETH)
            // -------------------------
            if (saleInfo.affiliation) {
            _handleAffiliate(_sponsor, msg.value);
    }
            emit TokensDebt(msg.sender, msg.value, tokenAmount);
        }


        function claim() external {
            _processClaim(msg.sender);
        }

        /**
        * @notice Claim purchased tokens on behalf of a user
        */
        function claimFor(address _user) external {
            _processClaim(_user);
        }

        /**
        * @notice Sponsor claims their ETH affiliate reward after finalize.
        */

        function claimSponsorReward() external nonReentrant { //make one read function  for Amount 
            require(saleInfo.affiliation, "Affiliate disabled");
            require(distributed,"Pool not finalized");
            require(!sponsorClaimed[msg.sender], "Already claimed");
            require(sponserReward[msg.sender]>0,"Nothing to claim");   
            uint256  reward =(sponserReward[msg.sender])-(sponserReward[msg.sender]*feePercent)/100;
            sponsorClaimed[msg.sender]=true;
            (bool success, ) = msg.sender.call{value: reward}("");
            require(success, "Reward Claim fail");
            emit SponsorRewardClaimed(msg.sender,reward);
        }

        function withdrawContribution() external nonReentrant {
            require(isPoolCancelled, "Pool not cancelled && soft cap is Meet    ");
            // require(totalInvestedETH < saleInfo.softCap, "Soft cap reached");
            UserInfo storage user = userInfo[msg.sender];
            uint256 amount = user.totalInvestedETH;
            require(amount > 0, "No investment");
            // reset user
            user.debt             = 0;
            user.totalInvestedETH = 0;//it may be change when sale is cancel 
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "Refund fail");
        }

        // --------------------------------------------------------------------------------
        // Owner-only functions
        // --------------------------------------------------------------------------------

        /**
        * @notice Finalize if successful (soft cap reached).
        */
        function finalize() external onlyOwner nonReentrant {
            require(!distributed, "Already finalized");
            require(
                totalInvestedETH >= saleInfo.hardCap || block.timestamp > timestamps.endTimestamp,
                "Sale not ended yet"
            ); 
            // if sale is filled before end time so admin can finalize  or if sale ended so admin can claim    
            require(totalInvestedETH >= saleInfo.softCap, "Soft cap not met");
                require(timestamps.claimTimestamp>0,"Frist set Claim Time");
                uint256 contributionRemain=totalInvestedETH;
                // 1. Deduct platform fee
                uint256 platformFee = (contributionRemain * feePercent) / 100;
                contributionRemain -= platformFee;
                (bool feeSent, ) = feeWallet.call{value: platformFee}("");
                require(feeSent, "Fee transferation fail");
                // 3. Handle unsold tokens
                uint256 unsoldToken = getUnsoldTokens();
                // if AutoListing Enable 
                if (saleInfo.lpInterestRate > 0 && saleInfo.listingPrice > 0) {
                    // calculate ETh for Lp
                    uint256 ethForLp = (contributionRemain * saleInfo.lpInterestRate) / 100;
                    contributionRemain -=  ethForLp;
                    // calculate Token for Lp
                uint256 tokenForLp = _getTokenAmount(
                        ethForLp,
                        saleInfo.listingPrice
                    );
                    // check unsold liquidity token
                    unsoldToken+=saleInfo.liquidityToken-tokenForLp;
                    // Add Liquidity ETH
                IUniswapV2Router02 uniswapRouter = IUniswapV2Router02(dexInfo.router);
                ERC20(saleInfo.rewardToken).approve(address(uniswapRouter), tokenForLp);
                (,, uint liquidity) = uniswapRouter.addLiquidityETH{value: ethForLp}(
                    address(saleInfo.rewardToken),
                    tokenForLp,
                    0, // slippage is unavoidable
                    0, // slippage is unavoidable
                    address(this),
                    block.timestamp + 360
                );
                    // Lock LP Tokens
                address lpTokenAddress = IUniswapV2Factory(dexInfo.factory).getPair(address(saleInfo.rewardToken), dexInfo.weth);
                ERC20 lpToken = ERC20(lpTokenAddress);
            
                if (timestamps.unlockTime > 0) {
                    lpToken.approve(address(locker), liquidity);
                    locker.lock(
                        msg.sender,
                        lpTokenAddress,
                        true,
                        liquidity,
                        timestamps.unlockTime+block.timestamp,
                        string.concat(lpToken.symbol(), " tokens locker")
                    );
                } else {
                    lpToken.transfer(msg.sender, liquidity);
                }
                    }
                //  Handle Affiliation logic 
                if(saleInfo.affiliation){
                    uint256 affilationReward=affiliateInfo.currentReward-((affiliateInfo.currentReward * feePercent) / 100);
                    affiliateInfo.totalRewardAmount=affilationReward;
                    contributionRemain-=affilationReward;
                }
        //    transfer unsold token
        if (unsoldToken > 0) {
                    if (saleInfo.burnType) {
                        ERC20(saleInfo.rewardToken).safeTransfer(0x000000000000000000000000000000000000dEaD, unsoldToken);
                    } else {
                    ERC20(saleInfo.rewardToken).safeTransfer(msg.sender, unsoldToken);
                    }
                }
        // Transfer fund to admin 
                (bool success, ) = msg.sender.call{value: contributionRemain}("");
                require(success, "Transfer failed.");
                distributed = true;
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
        function refundTokens() external onlyOwner {
            require(isPoolCancelled, "Pool is not canceled");
            uint256 balance =ERC20(saleInfo.rewardToken).balanceOf(address(this));
            require(balance > 0, "The IDO pool has not refund tokens.");
            ERC20(saleInfo.rewardToken).safeTransfer(msg.sender, balance);
        }
        /**
        * @notice Distribute purchased tokens in batch by admin
        */
        function distributeTokens() external onlyOwner {
            require(tokensForDistribution!=distributedTokens,"Token Already distributes");
            for (uint256 i = 0; i <participants.length;i++) {
                    UserInfo storage user = userInfo[participants[i]];
                    if(user.claimed==0){
                    _processClaim(participants[i]);
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
        * @notice Update start/end times if sale hasn't begun
        */
        function setEndAndStartTime(uint256 _start, uint256 _end) external onlyOwner {
            require(block.timestamp <= timestamps.startTimestamp, "Sale started");
            require(_start < _end, "Start < End");
            require(_start > block.timestamp, "Start in future");
            timestamps.startTimestamp = _start;
            timestamps.endTimestamp   = _end;
            emit TimestampsUpdated(_start, _end);
        }
        /**
        * @notice Set new claim time
        */
    function setClaimTime(uint256 _claimTimestamp) external onlyOwner {
            require(_claimTimestamp >= block.timestamp, "Claim time must be in the future or now");
            timestamps.claimTimestamp = _claimTimestamp;
    }

        /**
        * @notice Enable or disable whitelist and public 
        */
   
   
   
    function whitelistEnabled() external onlyOwner {
        require(!distributed, "Sale cannot be Enable WhiteListing after finalization");
        require(!saleInfo.isEnableWhiteList,"Sale Already WhiteListed");
        require(block.timestamp < timestamps.startTimestamp, "Cannot change whitelist settings after sale starts"); 
        saleInfo.isEnableWhiteList=true;
    }
        
    function publicSaleEanble() external onlyOwner{
        require(block.timestamp<=timestamps.endTimestamp,"sale is ended can't update public");
        require(!distributed, "cannot be Enable public  Sale after finalization");   
        require(saleInfo.isEnableWhiteList,"Sale Already WhiteListed");
        require(block.timestamp < timestamps.startTimestamp, "Cannot change public settings after sale starts"); 
        saleInfo.isEnableWhiteList=false;
    }

        /**
        * @notice Update the pool metadata
        */
    
    function setMetadataURL(string memory _url) external onlyOwner {
        saleInfo.metadataURL = _url;
    }

        /**
        * @notice Configure affiliate parameters (enabled & rate)
        * @param _enabled True if affiliate logic is active
        * @param _rate In basis points, e.g. 500 = 5%
        */
    
    function enableAffilate(bool _enabled, uint8 _rate) external  onlyOwner {
        // Sale status check
        require(getSaleStatus() == SaleStatus.Upcoming, "Can only enable before sale starts");
        require(_rate <= 5, "Affiliation rate max is 5%");
        saleInfo.affiliation = _enabled;
        affiliateInfo.realTimeRewardPercentage = _rate;
        affiliateInfo.maxReward=(saleInfo.hardCap*_rate)/100;

    }

        // --------------------------------------------------------------------------------
        // Public / view
        // --------------------------------------------------------------------------------

    function getParticipantsCount() external view returns (uint256) {
     return participants.length;
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
            if (totalInvestedETH >= saleInfo.hardCap) {
                return SaleStatus.Filled;
            } else {
                return SaleStatus.Live;
            }
        }
        return SaleStatus.Ended; // Fallback
    }

    function isSaleFilled() public view returns (bool) {
            return totalInvestedETH >= saleInfo.hardCap;
        }

        /**
        * @notice Return how many unsold tokens remain
        */
        function getUnsoldTokens() public view returns(uint256) {
            return saleInfo.presaleToken - tokensForDistribution;
        }

        function isAffiliation() external  view returns(bool){
            return saleInfo.affiliation;
        }

        // --------------------------------------------------------------------------------
        // Internal
        // --------------------------------------------------------------------------------
        function _processClaim(address _receiver) internal nonReentrant {
            require(!isPoolCancelled, "Cancelled");
            require(distributed, "Wait for Pool Finalize");
            require(block.timestamp >= timestamps.claimTimestamp, "Claim not started");
            require(totalInvestedETH >= saleInfo.softCap, "Soft cap not met");
            UserInfo storage user = userInfo[_receiver];
            uint256 amount = user.debt;
            require(amount > 0, "No tokens to claim");
            user.debt = 0;
            user.claimed += amount;

            distributedTokens += amount;

            ERC20(saleInfo.rewardToken).safeTransfer(_receiver, amount);
            emit TokensWithdrawn(_receiver, amount);
        }

    
    function _handleAffiliate(address _sponsor, uint256 amount) internal {
            if (_sponsor != address(0) && _sponsor != msg.sender) {
                if (sponsorReferralSum[_sponsor] == 0) {
                    sponeserAddress.push(_sponsor);
                    affiliateInfo.poolRefCount++;
                }
                sponsorReferralSum[_sponsor] += amount;
                uint256 reward = (affiliateInfo.realTimeRewardPercentage * amount) / 100;
                sponserReward[_sponsor] += reward;
                affiliateInfo.totalReferredAmount += amount;
                affiliateInfo.currentReward += reward;
            }
    }

    function _getTokenAmount(uint256 ethAmount, uint256 price) internal   view returns (uint256) {
            return (ethAmount * price ) / (10 ** tokenDecimals);
        }

    
    function getSaleType() external view returns (string memory) {
        return saleInfo.isEnableWhiteList ? "Whitelist" : "Public";
    }

    function getAllParticipant () external view returns(address [] memory){
        return  participants;
    }
    
    function isSalePublic() external view returns (bool) {
        return !saleInfo.isEnableWhiteList;
    }

    function getTotalParticipantCount() external view returns(uint256){
        return participants.length;
    }

    function getClaimableTokenAmount(address _user) external view returns (uint256) { 
        UserInfo storage user = userInfo[_user];
        return user.debt;
    }

    function isPoolUser(address _user) external view returns ( bool){
        UserInfo storage user = userInfo[_user];
        return user.totalInvestedETH>0?true :false;
    }

    function isPoolCancel() external view  returns(bool){
        return  isPoolCancelled;
    }

    function getClaimedTokenAmount (address _user) external view returns (uint256){
        UserInfo storage user = userInfo[_user];
        return  user.claimed;
    }
    
    function getTotalInvesment() external view returns(uint256){
        return  totalInvestedETH;
    }

    function getFeePecetage() external view returns (uint8){
    return feePercent;
    }

    function getSaleInfo() external view returns (SaleInfo memory){
        return saleInfo;
    }
    
    function getTimesatmpInfo() external view returns  (Timestamps memory){
        return timestamps;
    }
    
    function getAllSponesers() external view returns (address[] memory) {
        return sponeserAddress;
    }

    function getSponserRewardAmount(address _sponsor) external view returns (uint256) {
        if (sponsorClaimed[_sponsor]) return 0;
        uint256 raw = sponserReward[_sponsor];
        uint256 fee = (raw * feePercent) / 100;
        return raw - fee;
    }

    function getSponsorReferralSum(address _sponser) external view returns (uint256) {
        return sponsorReferralSum[_sponser];
    }

    function getAffiliateInfo() external view returns (AffiliateInfo memory) {
        return affiliateInfo;
    }

    function getIsSponsorClaimed(address _sponser) external view returns (bool) {
        return sponsorClaimed[_sponser];
    }

    function getUserInvesmentAmount(address _user) external view returns (uint256){
        UserInfo storage user = userInfo[_user];
        return user.totalInvestedETH;
    }

    function isPoolFinalize() external view  returns (bool){
        return distributed;
    }

    function recoverWrongTokens(address _tokenAddress, uint256 _tokenForLp) external onlyOwner {
            require(_tokenAddress != address(saleInfo.rewardToken), "Cannot recover sale token");
            ERC20(_tokenAddress).safeTransfer(msg.sender, _tokenForLp);
        }

    
   
    function recoverNativeTokens(uint256 tokenAmount) public onlyOwner {
            payable(owner()).transfer(tokenAmount);
        }

    }
