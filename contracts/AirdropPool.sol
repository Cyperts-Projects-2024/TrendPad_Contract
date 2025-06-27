    // SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract AirdropPool is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
using SafeERC20 for ERC20;

// Track allocations
mapping(address => uint256) public Allocations; // total allocated per user
mapping(address => uint256) public claimed;     // total claimed by each user

enum AirdropState {
    Upcoming,
    Live,
    Ended,
    Cancelled
}
struct Airdrop {
    address tokenAddress;
    uint256 startTime; // TGE start time
    uint8 tgePercent; // immediate % at TGE
    uint8 cyclePercent; // % each cycle
    uint256 cycleTime; // length of each cycle in seconds
    uint8 totalparticipants;
    uint256 totalAllocationAmount; // total tokens allocated across all users
    uint256 totalClaimed; // total tokens already claimed/distributed
    string metaData;
}


Airdrop public airdrop;
bool public isCancelled;
address[] public allocatedAddresses; 

// ------------------------------------------------
// Events
// ------------------------------------------------
event AllocationSet(address indexed beneficiary, uint256 amount);
event AirdropStarted(uint256 startTime);
event AirdropCancelled(address indexed account);
event VestingEnabled(uint8 tgePercent, uint8 cyclePercent, uint256 cycleTime);
event AirdropEnded();
event TokensClaimed(address user, uint256 amount);


    function initialize(
        address _tokenAddress,
        string memory _metaUrl
    ) public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();        
        // Initialize state variables
        airdrop.tokenAddress = _tokenAddress;
        airdrop.metaData = _metaUrl;
        isCancelled = false;
    }
    
function setAllocation(
    address[] calldata _allocationAddress,
    uint256[] calldata _amounts
) external onlyOwner {
    require(
      getAirdropState() ==AirdropState.Upcoming,
        "Allocations can only be set before the airdrop starts"
    );
    require(
        _allocationAddress.length > 0 && _amounts.length > 0,
        "Allocation arrays empty"
    );
    require(
        _allocationAddress.length == _amounts.length,
        "Array length mismatch"
    );
    for (uint256 i = 0; i < _allocationAddress.length; i++) {
        if(Allocations[_allocationAddress[i]] == 0)
  {
            allocatedAddresses.push(_allocationAddress[i]);
            airdrop.totalparticipants++;
        }

        airdrop.totalAllocationAmount = airdrop.totalAllocationAmount+_amounts[i];
        
        Allocations[_allocationAddress[i]] = Allocations[_allocationAddress[i]]+_amounts[i];
        emit AllocationSet(_allocationAddress[i], _amounts[i]);
    }
}

function setVesting(
    uint8 _tgePercent,
    uint8 _cyclePercent,
    uint256 _cycleTime
) external onlyOwner {
    require(
        getAirdropState() == AirdropState.Upcoming,
        "Vesting can only be set before the airdrop starts"
    );
    require(_tgePercent > 0 &&_tgePercent <= 100, "Invalid TGE %");
    require(_cyclePercent>0 &&_cyclePercent <= 100, "Invalid cycle Percentage %");
    require(_tgePercent + _cyclePercent <= 100, "Total percentage exceeds 100%");
    require(_cycleTime >= 60, "Cycle time must be at least 1 Mintues");
    airdrop.tgePercent = _tgePercent;
    airdrop.cyclePercent = _cyclePercent;
    airdrop.cycleTime = _cycleTime;
    emit VestingEnabled(_tgePercent, _cyclePercent, _cycleTime);
}

function remove_ALL_Allocation() external onlyOwner {
    require(
        getAirdropState() == AirdropState.Upcoming,
        "Can only remove allocations before the airdrop starts"
    );
    require(allocatedAddresses.length > 0, "No user allocated");
    for (uint256 i = 0; i < allocatedAddresses.length; i++) {
        address user = allocatedAddresses[i];
        Allocations[user] = 0;
    }
    airdrop.totalAllocationAmount = 0;
    airdrop.totalClaimed = 0;
    airdrop.totalparticipants = 0;
    delete allocatedAddresses;
}

function startAirdrop(uint256 _startTime) external onlyOwner {
    require(
        getAirdropState() == AirdropState.Upcoming,
        "Airdrop already started or ended or cancelled"
    );
    require(airdrop.totalAllocationAmount > 0, "No tokens to Airdrop");
    require(block.timestamp <= _startTime, "Time should be in the future");
    require(
        ERC20(airdrop.tokenAddress).balanceOf(msg.sender) >= airdrop.totalAllocationAmount,
        "Insufficient amount in your wallet"
    );
    airdrop.startTime = _startTime;

    ERC20(airdrop.tokenAddress).safeTransferFrom(
        msg.sender,
        address(this),
        airdrop.totalAllocationAmount
    );
    emit AirdropStarted(_startTime);
}

function cancelAirdrop() external onlyOwner {
    require(
        getAirdropState() == AirdropState.Upcoming,
        "Airdrop cannot be cancelled Now"
    );
    isCancelled=true;
    emit AirdropCancelled(msg.sender);
}

function claim() external nonReentrant {
    require(getAirdropState() == AirdropState.Live, "Airdrop not live");
    uint256 userAllocation = Allocations[msg.sender];
    require(userAllocation > 0, "No allocation");
    
    uint256 unlocked = _unlockedTokens(msg.sender);
    require(unlocked > 0, "Nothing unlocked yet");
    
    claimed[msg.sender] = claimed[msg.sender]+unlocked;
    airdrop.totalClaimed = airdrop.totalClaimed+unlocked;
    
    ERC20(airdrop.tokenAddress).safeTransfer(msg.sender, unlocked);

    emit TokensClaimed(msg.sender,unlocked);
}

function withdrawableTokens(address user) external view returns (uint256) {
    return _unlockedTokens(user);
}

function nextClaimTime(address user) external view returns (uint256) {
            if (
            getAirdropState() != AirdropState.Live||
                Allocations[user] == 0 ||
                airdrop.tgePercent == 0
            ) {
                return 0;
            }
            if (block.timestamp < airdrop.startTime) {
                return airdrop.startTime;
            }
            uint256 unlockedSoFar = _unlockedTokensSoFar(user); // total that should be unlocked (not subtracting claimed)
            uint256 userClaimed = claimed[user];
            if (unlockedSoFar > userClaimed) {
                return 0;
            }
            if (unlockedSoFar == Allocations[user]) {
                return 0;
            }
            uint256 timeSinceStart = block.timestamp - airdrop.startTime;
            uint256 cyclesElapsed = timeSinceStart / airdrop.cycleTime;
            uint256 nextCycle = cyclesElapsed + 1;
            uint256 nextCycleTimestamp = airdrop.startTime +
                (nextCycle * airdrop.cycleTime);
            return nextCycleTimestamp;
        }

function _unlockedTokens(address user) internal view returns (uint256) {
            uint256 totalUnlockedSoFar = _unlockedTokensSoFar(user);
            uint256 alreadyClaimed = claimed[user];
            if (totalUnlockedSoFar <= alreadyClaimed) {
                return 0;
            }
            return totalUnlockedSoFar-alreadyClaimed;
        }

function _unlockedTokensSoFar(address user) internal view returns (uint256) {
        uint256 totalAlloc = Allocations[user];
        if (totalAlloc == 0) {
            return 0;
        }
        // If vesting is not set (tgePercent == 0), then unlock 100% immediately.
        if (airdrop.tgePercent == 0) {
            return totalAlloc;
        }
   
        // TGE portion (vesting enabled)
        uint256 tgePortion = (totalAlloc * airdrop.tgePercent) / 100;
        uint256 totalUnlockedSoFar = tgePortion; 
        // Calculate unlocked tokens from cycles
        uint256 timeSinceTGE = block.timestamp-airdrop.startTime;
        if (timeSinceTGE > 0 && airdrop.cycleTime > 0 && airdrop.cyclePercent > 0) {
            uint256 cyclesElapsed = timeSinceTGE / (airdrop.cycleTime);
            uint256 cycleUnlockPerCycle = (totalAlloc * airdrop.cyclePercent)/ (100);
            uint256 totalCycleUnlock = cycleUnlockPerCycle * cyclesElapsed;
            totalUnlockedSoFar = totalUnlockedSoFar + totalCycleUnlock;
            // Cap at full allocation
            if (totalUnlockedSoFar > totalAlloc) {
                totalUnlockedSoFar = totalAlloc;
            }
        }
        return totalUnlockedSoFar;
    }

function getTotalAllocationAmount() external view returns (uint256) {
        return airdrop.totalAllocationAmount;
}

function getTotalClaimed() external  view returns (uint256) {
        return airdrop.totalClaimed;
    }

function getUserAllocation (address _user)  view external returns (uint256) {
    return Allocations[_user];
    }

function getUserClaimed(address _user) view  external  returns (uint256){
        return  claimed[_user];
    } 

function getPoolDetails() public view returns (Airdrop memory){
        return airdrop;
}

function getSaleStartTime() external  view returns (uint256) {
        return airdrop.startTime;
    }

function getTotalParticipantCount() external view returns (uint256)
        {
            return  airdrop.totalparticipants ;
        }

function getAllAllocation() external view  returns (address [] memory){
      return allocatedAddresses;
    }
  
function getAirdropState() public view returns (AirdropState) {
    // If cancelled, return immediately
    if (isCancelled) {
        return  AirdropState.Cancelled;
    }        
    if (airdrop.startTime == 0) {
    return AirdropState.Upcoming;  
     }
    if (block.timestamp < airdrop.startTime) {
        return AirdropState.Upcoming;
    }
    if (airdrop.totalClaimed >= airdrop.totalAllocationAmount) {
        return AirdropState.Ended;
    }
      return AirdropState.Live;
}    
}
        