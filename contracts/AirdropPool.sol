        // SPDX-License-Identifier: MIT
        pragma solidity ^0.8.0;
        import "@openzeppelin/contracts/access/Ownable.sol";
        import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
        import "@openzeppelin/contracts/utils/math/SafeMath.sol";
        import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
        import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
        import "hardhat/console.sol";

        contract AirdropPool is Ownable, ReentrancyGuard {
            using SafeMath for uint256;
            using SafeERC20 for ERC20;
            // Track allocations
            mapping(address => uint256) public Allocations; // total allocated per user
            mapping(address => uint256) public claimed; // total claimed by each user
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
                AirdropState state;
                string  metaData;
            }

            struct AllocationRecord{
            address user;
            uint256 amount;
               }  
            Airdrop public airdrop;
            AllocationRecord[] public allocationRecords;
            // ------------------------------------------------
            // Events
            // ------------------------------------------------
            event AllocationSet(address indexed beneficiary, uint256 amount);
            event AirdropStarted(uint256 startTime);
            event AirdropCancelled(address indexed account);
            event VestingEnabled(
                uint8 tgePercent,
                uint8 cyclePercent,
                uint256 cycleTime
            );
            event AirdropEnded(); // New event when all distribution is done

            // ------------------------------------------------
            // Constructor
            // ------------------------------------------------
            constructor(address _tokenAddress,string memory _metaData
            ) Ownable(msg.sender) {
            airdrop.tokenAddress=_tokenAddress;
            airdrop.metaData=_metaData;
            airdrop.state = AirdropState.Upcoming; // Initial state
            }

    function setAllocation(
                address[] calldata _allocationAddress,
                uint256[] calldata _amounts
            ) external onlyOwner {
                require(
                    airdrop.state == AirdropState.Upcoming,
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
                    allocationRecords.push(AllocationRecord({
                    user: _allocationAddress[i],
                    amount: _amounts[i]
                  }));
                    // Increase totalAllocationAmount
                    airdrop.totalAllocationAmount = airdrop.totalAllocationAmount.add(
                        _amounts[i]
                    );
                    // increase totalparticipants Count

                    airdrop.totalparticipants++;

                    // Set user allocation
                    Allocations[_allocationAddress[i]] = Allocations[_allocationAddress[i]].add(_amounts[i]);

                    emit AllocationSet(_allocationAddress[i], _amounts[i]);
                }
            }
            
    function setVesting(
                uint8 _tgePercent,
                uint8 _cyclePercent,
                uint256 _cycleTime
            ) external onlyOwner {
                require(
                    airdrop.state == AirdropState.Upcoming,
                    "Vesting can only be set before the airdrop starts"
                );
                require(_tgePercent <= 100, "Invalid TGE %");
                require(_cyclePercent <= 100, "Invalid cycle %");
                require(_cycleTime >= 60, "Invalid cycle time");
                airdrop.tgePercent = _tgePercent;
                airdrop.cyclePercent = _cyclePercent;
                airdrop.cycleTime = _cycleTime;
                emit VestingEnabled(_tgePercent, _cyclePercent, _cycleTime);
            }
            
    function remove_ALL_Allocation() external onlyOwner {
        require(allocationRecords.length > 0, "No user allocated");
        // Loop through each allocation record and reset mappings for that user
        for (uint256 i = 0; i < allocationRecords.length; i++) {
            address user = allocationRecords[i].user;
            Allocations[user] = 0;
            claimed[user] = 0;
        }
        // Reset overall airdrop totals
        airdrop.totalAllocationAmount = 0;
        airdrop.totalClaimed = 0;
        // Delete the allocationRecords array from storage
        delete allocationRecords;
}


    function startAirdrop(uint256 _startTime) external onlyOwner {
                require(
                    airdrop.state == AirdropState.Upcoming,
                    "Airdrop already started or ended"
                );
                require(airdrop.totalAllocationAmount > 0, "No tokens to Airdrop");
                require(block.timestamp <= _startTime, "Time should be in the future");

                // Transfer tokens from the owner to the contract
                require(
                ERC20(airdrop.tokenAddress).balanceOf(msg.sender) >= airdrop.totalAllocationAmount,
                    "Insufficient amount in your wallet"
                );

                airdrop.startTime = _startTime;
                airdrop.state = AirdropState.Live; // Transition to Live state

              ERC20(airdrop.tokenAddress).safeTransferFrom(
                    msg.sender,
                    address(this),
                    airdrop.totalAllocationAmount
                );

                emit AirdropStarted(_startTime);
            }

    function cancelAirdrop() external onlyOwner {
                require(
                    airdrop.state == AirdropState.Upcoming,
                    "Airdrop cannot be cancelled"
                );
                airdrop.state = AirdropState.Cancelled; // Transition to Cancelled state
                emit AirdropCancelled(msg.sender);
            }
        
                
    function claim() external nonReentrant {
                require(airdrop.state == AirdropState.Live, "Airdrop not live");
                uint256 userAllocation = Allocations[msg.sender];
                require(userAllocation > 0, "No allocatifon");
                        uint256 unlocked = _unlockedTokens(msg.sender);
                        require(unlocked > 0, "Nothing unlocked yet");
                        // Increase claimed
                        claimed[msg.sender] = claimed[msg.sender].add(unlocked);
                        // Increase totalClaimed
                        airdrop.totalClaimed = airdrop.totalClaimed.add(unlocked);
                        // Transfer
                        ERC20(airdrop.tokenAddress).safeTransfer(msg.sender, unlocked);
                    // If we've distributed all tokens, end the airdrop
                    if (airdrop.totalClaimed >= airdrop.totalAllocationAmount) {
                        airdrop.state = AirdropState.Ended;
                        emit AirdropEnded();
                    }
            }
        
    function withdrawableTokens(address user) external view returns (uint256) {
                    return _unlockedTokens(user);
            }

    function nextClaimTime(address user) external view returns (uint256) {
                if (
                    airdrop.state != AirdropState.Live ||
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
                console.log("Data Not geeting");
                if (totalUnlockedSoFar <= alreadyClaimed) {
                    console.log("DATA2");
                    return 0;
                }
                return totalUnlockedSoFar.sub(alreadyClaimed);
            }

    function _unlockedTokensSoFar(address user) internal view returns (uint256) {
            uint256 totalAlloc = Allocations[user];
            console.log("Data Not geeting-111");
            if (totalAlloc == 0) {
                return 0;
            }
            // If vesting is not set (tgePercent == 0), then unlock 100% immediately.
            if (airdrop.tgePercent == 0) {
                console.log("Data Not geeting--222");
                return totalAlloc;
            }
            // If TGE hasn't started, nothing is unlocked.
            if (block.timestamp < airdrop.startTime) {
            console.log("Data Not geeting--4");
                return 0;
            }
            // TGE portion (vesting enabled)
            uint256 tgePortion = totalAlloc.mul(airdrop.tgePercent).div(100);
            uint256 totalUnlockedSoFar = tgePortion; 
            // Calculate unlocked tokens from cycles
            uint256 timeSinceTGE = block.timestamp.sub(airdrop.startTime);
            if (timeSinceTGE > 0 && airdrop.cycleTime > 0 && airdrop.cyclePercent > 0) {
                console.log("Data Not geeting-final");
                uint256 cyclesElapsed = timeSinceTGE.div(airdrop.cycleTime);
                uint256 cycleUnlockPerCycle = totalAlloc.mul(airdrop.cyclePercent).div(100);
                uint256 totalCycleUnlock = cycleUnlockPerCycle.mul(cyclesElapsed);
                totalUnlockedSoFar = totalUnlockedSoFar.add(totalCycleUnlock);
                // Cap at full allocation
                if (totalUnlockedSoFar > totalAlloc) {
                    console.log("Data Not geeting--44");
                    totalUnlockedSoFar = totalAlloc;
                }
            }
            return totalUnlockedSoFar;
        }

    function getAirdropState() public view returns (string memory) {
            if (airdrop.state == AirdropState.Upcoming) return "Upcoming";
            if (airdrop.state == AirdropState.Live) return "Live";
            if (airdrop.state == AirdropState.Ended) return "Ended";
            if (airdrop.state == AirdropState.Cancelled) return "Cancelled";
            return "Unknown";
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

    function getAllAllocation() external view  returns (AllocationRecord [] memory){
          return allocationRecords;
        }
        }
        