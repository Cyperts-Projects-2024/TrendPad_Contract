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
        uint256 tokenAmount;
        uint256 softCap;
        uint256 maxPay;
        uint256 lpPayPercent;
    }

    struct Timestamps {
        uint256 startTimestamp;  
        uint256 endTimestamp;    
        uint256 claimTimestamp;  
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

    struct Tier {
        uint256 startTime;    // When this tier starts
        uint256 endTime;      // When this tier ends
    }

    // Whitelist settings
    enum WhitelistType { DISABLED, BASIC, TIERED }
    
    WhitelistType public whitelistType = WhitelistType.DISABLED;
    uint256 public publicSaleTime; // Time when the sale becomes public (0 if no public phase)
    
    // Basic whitelist
    mapping(address => bool) public whitelist;
    
    // Tiered whitelist
    Tier[4] public tiers;
    mapping(uint8 => mapping(address => bool)) public tierWhitelists; // Tier => User => IsWhitelisted
    mapping(uint8 => address[]) public tierUsers;
    uint8 public activeTierCount = 0;

    ERC20 public saleToken;
    uint256 public decimals;
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
    address[] public participants;
    bool public distributed = false;
    
    mapping(address => UserInfo) public userInfo;
    
    event TokenDebt(address indexed holder, uint256 ethAmount, uint256 tokenAmount);
    event PoolCancelled(uint timestamps);
    event TokenWithdraw(address indexed holder, uint256 amount);
    event EndTimestampsUpdated(uint256 _newEndTime);
    event TimestampsUpdated(uint256 _newStartTime, uint256 _newEndTime);
    event WhitelistTypeUpdated(WhitelistType whitelistType, uint256 publicSaleTime);
    event WhitelistUpdated(address[] users, bool isAdded);
    event TierCreated(uint8 tierId, uint256 endTime);
   
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
        saleToken = _saleTokenAddress;
        decimals = saleToken.decimals();
        locker = ITrendLock(_lockerAddress);
        feeWallet = _feeWallet;
        feePercent = _feePercent;
        saleInfo = _saleInfo;
        setTimestamps(_timestamps);
        dexInfo = _dexInfo;
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

    function setMetadataURL(string memory _metadataURL) public onlyOwner {
        metaDataURl = _metadataURL;
    }

    // Check if an address can participate based on whitelist settings
    function canParticipate(address _user) public view returns (bool, uint256) {
        // If whitelist is disabled, it's a normal sale - anyone can participate
        if (whitelistType == WhitelistType.DISABLED) {
            return (true, saleInfo.maxPay);
        }
        
        // Public sale check
        if (publicSaleTime > 0 && block.timestamp >= publicSaleTime) {
            return (true, saleInfo.maxPay);
        }

        if (whitelistType == WhitelistType.BASIC) {
            return (whitelist[_user], saleInfo.maxPay);
        }

        if (whitelistType == WhitelistType.TIERED) {
            // Check which tier is active based on block.timestamp
            for (uint8 i = 0; i < activeTierCount; i++) {
                if (block.timestamp >= tiers[i].startTime && block.timestamp <= tiers[i].endTime) {
                    // User is in this tier
                    if (tierWhitelists[i][_user]) {
                        return (true, saleInfo.maxPay);
                    }
                }
            }
        }

        return (false, 0);
    }

    function pay() payable external {
        require(block.timestamp >= timestamps.startTimestamp, "Sale not started yet");
        require(block.timestamp < timestamps.endTimestamp, "Sale ended");
        
        // Check whitelist
        (bool allowed, uint256 maxAllocation) = canParticipate(msg.sender);
        require(allowed, "Not whitelisted for current phase");
        
        UserInfo storage user = userInfo[msg.sender];
        
        // Only check max contribution if maxPay is set (not zero)
        if (maxAllocation > 0) {
            require(msg.value <= maxAllocation, "Exceeds your allocation");
            require(user.totalInvestedETH.add(msg.value) <= maxAllocation, "Exceeds your total allocation");
        }
        
        totalInvestedEth = totalInvestedEth.add(msg.value);
        user.totalInvestedETH = user.totalInvestedETH.add(msg.value);
        user.debt = user.debt.add(msg.value); 
        
        // Track participants if first time
        if (user.totalInvestedETH == msg.value) {
            participants.push(msg.sender);
        }
        
        emit TokenDebt(msg.sender, msg.value, msg.value);
    }

    // Calculate tokens on basis of userContribution 
    function getTokenPrice(uint _userContribution) public view returns (uint256) {
        return _userContribution.mul(saleInfo.tokenAmount).div(totalInvestedEth);
    }

    // Calculate current tokens Rate  
    function CurrentTokenRate() public view returns (uint256) {
        uint256 scale = 10**18;
        return saleInfo.tokenAmount.mul(scale).div(totalInvestedEth);
    }
    
    function claimFor(address _user) external {
        proccessClaim(_user);
    }

    function claim() external {
        proccessClaim(msg.sender);
    }

    function proccessClaim(address _receiver) public nonReentrant {
        require(block.timestamp > timestamps.endTimestamp, "The IDO pool has not ended.");
        require(totalInvestedEth >= saleInfo.softCap, "The IDO pool did not reach soft cap.");
        require(distributed, "Wait for Pool Finalize");
        require(block.timestamp >= timestamps.claimTimestamp, "Claim period has not started yet.");
        
        UserInfo storage user = userInfo[_receiver];
        uint256 _amount = user.debt;
        require(_amount > 0, "You do not have contributions"); 
        
        uint256 tokenAmount = getTokenPrice(_amount);
        user.debt = 0;
        user.total = tokenAmount;
        distributedTokens = distributedTokens.add(_amount);
        saleToken.safeTransfer(_receiver, tokenAmount);
        
        emit TokenWithdraw(_receiver, _amount);
    }

    function Finalize() external payable onlyOwner {
        require(block.timestamp > timestamps.endTimestamp, "The IDO pool has not ended.");
        require(totalInvestedEth >= saleInfo.softCap, "The IDO pool did not reach soft cap.");
        require(!distributed, "Already distributed.");
        
        uint256 contractBalance = address(this).balance;
        require(contractBalance == totalInvestedEth, "Contract balance does not match");
        
        uint256 platformFee = contractBalance.mul(feePercent).div(10000);
        contractBalance = contractBalance.sub(platformFee);  
        
        (bool feeTransferSuccess, ) = feeWallet.call{value: platformFee}("");
        require(feeTransferSuccess, "Platform fee transfer failed");
        
        uint256 balance = address(this).balance;
        require(balance > 0, 'Not enough funds in pool');

        uint256 ethForLP = (balance * saleInfo.lpPayPercent) / 100;
        uint256 ethWithdraw = balance - ethForLP;

        uint256 tokenAmount = getFairLaunchTokenAmount(saleInfo.tokenAmount, saleInfo.lpPayPercent, decimals);
       
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
        address lpTokenAddress = IUniswapV2Factory(dexInfo.factory).getPair(address(saleToken), dexInfo.weth);
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
            ethWithdraw += msg.value;
        }

        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "Transfer failed.");
        
        distributed = true;
    }

    // After sale cancel admin can withdraw their token
    function withdrawToken() external onlyOwner {
        require(IsPoolCancel, "Pool is not canceled");
        uint256 balance = saleToken.balanceOf(address(this));
        require(balance > 0, "The IDO pool has not refund tokens.");
        saleToken.safeTransfer(msg.sender, balance);
    }
    
    // After sale cancel user can claim their contribution
    function claimContribution() external nonReentrant {
        require(IsPoolCancel, "Pool not cancelled");
        
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.totalInvestedETH;
        require(amount > 0, "No investment");
        
        // Reset user
        user.debt = 0;
        user.total = 0;
        user.totalInvestedETH = 0;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Refund fail");
    }

    // Admin can cancel before sale end time 
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
        emit EndTimestampsUpdated(_endTimestamp);
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
        require(_claimTimestamp >= block.timestamp, "Claim time must be in the future or now");
        timestamps.claimTimestamp = _claimTimestamp;
    }
   
    function distributeTokens() external onlyOwner {
        require(distributed, "First finalize pool to distribute tokens");
        for (uint256 i = 0; i < participants.length; i++) {
            proccessClaim(participants[i]);
        }
    }

    //---------------------------
    // Whitelist Management
    //---------------------------

    // Set whitelist type and public sale time
    function setNormalWhiteList(uint256 _publicSaleTime) external onlyOwner {
        require(block.timestamp < timestamps.startTimestamp, "Cannot change whitelist settings after sale starts");
        whitelistType = WhitelistType.BASIC;
        if (_publicSaleTime > 0) {
            require(_publicSaleTime >= timestamps.startTimestamp, "Public sale time must be after sale start");
            require(_publicSaleTime < timestamps.endTimestamp, "Public sale time must be before sale end");
            publicSaleTime = _publicSaleTime;
        } else {
            publicSaleTime = 0;
        }
        
    }

    // Add or remove addresses from basic whitelist
    function updateWhitelist(address[] calldata _users, bool _isWhitelisted) external onlyOwner {
        require(whitelistType == WhitelistType.BASIC, "Whitelist type must be BASIC");
        
        for (uint256 i = 0; i < _users.length; i++) {
            whitelist[_users[i]] = _isWhitelisted;
        }
        
        emit WhitelistUpdated(_users, _isWhitelisted);
    }

    // Setup tiers with end times only
    function setTiers(uint256[] calldata _endTimes) external onlyOwner {
        require(_endTimes.length > 0 && _endTimes.length <= 4, "Invalid tier count");
        require(block.timestamp < timestamps.startTimestamp, "Cannot update tiers after sale starts");
        
        // Automatically set whitelist type to TIERED if it wasn't already
        if (whitelistType != WhitelistType.TIERED) {
            whitelistType = WhitelistType.TIERED;
            emit WhitelistTypeUpdated(WhitelistType.TIERED, publicSaleTime);
        }
        
        // Validate end times
        for (uint8 i = 0; i < _endTimes.length; i++) {
            require(_endTimes[i] > timestamps.startTimestamp, "Tier end time must be after sale start");
            require(_endTimes[i] < timestamps.endTimestamp, "Tier end time must be strictly before sale end");
            
            // Ensure tiers are in chronological order
            if (i > 0) {
                require(_endTimes[i] > _endTimes[i-1], "Tiers must be in chronological order");
            }
            
            // Set tier end time
            tiers[i].endTime = _endTimes[i];
            
            // Set tier start time (first tier starts at sale start, others start when previous tier ends)
            if (i == 0) {
                tiers[i].startTime = timestamps.startTimestamp;
            } else {
                tiers[i].startTime = _endTimes[i-1];
            }
            
            emit TierCreated(i, _endTimes[i]);
        }
        
        activeTierCount = uint8(_endTimes.length);
    }
    


    // Set whitelist users for a specific tier
    function setTierWhitelist(uint8 _tierId, address[] calldata _users, bool _isWhitelisted) external onlyOwner {
        require(whitelistType == WhitelistType.TIERED, "Whitelist type must be TIERED");
        require(_tierId < activeTierCount, "Invalid tier ID");
        require(block.timestamp < timestamps.startTimestamp, "Cannot update whitelist after sale starts");
        
        for (uint256 i = 0; i < _users.length; i++) {
            tierWhitelists[_tierId][_users[i]] = _isWhitelisted;
            
            // Track users in this tier if not already tracked and being added
            if (_isWhitelisted) {
                bool userExists = false;
                for (uint256 j = 0; j < tierUsers[_tierId].length; j++) {
                    if (tierUsers[_tierId][j] == _users[i]) {
                        userExists = true;
                        break;
                    }
                }
                
                if (!userExists) {
                    tierUsers[_tierId].push(_users[i]);
                }
            }
        }
        
        emit WhitelistUpdated(_users, _isWhitelisted);
    }

    // Get all users in a tier
    function getTierUsers(uint8 _tierId) external view returns (address[] memory) {
        require(_tierId < activeTierCount, "Invalid tier ID");
        return tierUsers[_tierId];
    }

    // Check if a user is whitelisted for a specific tier
    function isTierWhitelisted(uint8 _tierId, address _user) external view returns (bool) {
        require(_tierId < activeTierCount, "Invalid tier ID");
        return tierWhitelists[_tierId][_user];
    }
    

}