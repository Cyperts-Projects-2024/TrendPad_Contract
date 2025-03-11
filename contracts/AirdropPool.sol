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

    // ------------------------------------------------
    // State Variables
    // ------------------------------------------------
    ERC20 public tokenAddress;
    string public metaurl;
    address public adminWallet;

    // Track allocations
    address[] public allocatedAddress;
    mapping(address => uint256) public Allocations; // total allocated per user
    mapping(address => uint256) public claimed;     // total claimed by each user

    struct Airdrop {
        uint256 startTime;        // TGE start time
        uint8 tgePercent;         // immediate % at TGE
        uint8 cyclePercent;       // % each cycle
        uint256 cycleTime;        // length of each cycle in seconds
        bool isLive;              // airdrop active or not
        uint256 totalDistibution; // total tokens allocated across all users
        uint256 totalDistributed; // total tokens already claimed/distributed
    }

    Airdrop public airdrop;

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
    constructor(
        ERC20 _tokenAddress,
        string memory _metaUrl,
        address _adminWallet
    )
    {
        adminWallet = _adminWallet;
        tokenAddress = _tokenAddress;
        metaurl = _metaUrl;
    }

    // ------------------------------------------------
    // Owner Functions
    // ------------------------------------------------

    function setAllocation(
        address[] calldata _allocationAddress,
        uint256[] calldata _amounts
    ) external onlyOwner {
        require(
            _allocationAddress.length > 0 && _amounts.length > 0,
            "Allocation arrays empty"
        );
        require(
            _allocationAddress.length == _amounts.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < _allocationAddress.length; i++) {
            address user = _allocationAddress[i];
            allocatedAddress.push(user);

            // Increase totalDistibution
            airdrop.totalDistibution = airdrop.totalDistibution.add(_amounts[i]);
            
            // Set user allocation
            Allocations[user] = Allocations[user].add(_amounts[i]);

            emit AllocationSet(user, _amounts[i]);
        }
    }
    
    function remove_ALL_Allocation() external onlyOwner {
        require(allocatedAddress.length > 0, "No user allocated");

        // Reset each user's allocation and claimed amounts
        for (uint256 i = 0; i < allocatedAddress.length; i++) {
            address user = allocatedAddress[i];
            Allocations[user] = 0;
            claimed[user] = 0;
        }
        airdrop.totalDistibution = 0;
        airdrop.totalDistributed = 0;

        delete allocatedAddress;
    }

    /**
     * @dev Configure TGE-based vesting. 
     * @param _tgePercent The % to unlock at TGE (0-100)
     * @param _cyclePercent The % to unlock each cycle (0-100)
     * @param _cycleTime Length of each cycle in seconds (must be >= 60 in your requirement)
     */
    function setVesting(
        uint8 _tgePercent,
        uint8 _cyclePercent,
        uint256 _cycleTime
    ) external onlyOwner {
        require(!airdrop.isLive, "You cant't update after airdrop live");
        require(_tgePercent <= 100, "Invalid TGE %");
        require(_cyclePercent <= 100, "Invalid cycle %");
        require(_cycleTime >= 60, "Invalid cycle time");

        airdrop.tgePercent = _tgePercent;
        airdrop.cyclePercent = _cyclePercent;
        airdrop.cycleTime = _cycleTime;

        emit VestingEnabled(_tgePercent, _cyclePercent, _cycleTime);
    }

    /**
     * @dev Start the airdrop (transfer tokens in). This sets the airdrop to live 
     *      and sets `startTime` if we want the TGE to be "now".
     * @param _startTime Usually you'd want a future time. 
     *        But in your code, you require block.timestamp >= _startTime (which is unusual).
     */
    function startAirdrop(uint256 _startTime) external onlyOwner {
        require(!airdrop.isLive, "Airdrop already live");
        require(airdrop.totalDistibution > 0, "No tokens to Airdrop");
        // NOTE: The code below requires that the current time is >= _startTime, 
        // which is the OPPOSITE of a typical "must be in the future" check.
        // Double-check the logic you want here.
       require(block.timestamp <= _startTime, "Time should be In Future");
        // Transfer tokens from the owner to the contract
        require(
            tokenAddress.balanceOf(msg.sender) >= airdrop.totalDistibution,
            "Insufficient amount in your wallet"
        );
        airdrop.startTime = _startTime;
        airdrop.isLive = true;

        tokenAddress.safeTransferFrom(
            msg.sender,
            address(this),
            airdrop.totalDistibution
        );

        emit AirdropStarted(_startTime);
    }

    
    function cancelAirdrop() external onlyOwner {
        airdrop.isLive = false;
        emit AirdropCancelled(msg.sender);
    }

    // ------------------------------------------------
    // Public Claim Logic
    // ------------------------------------------------

    /**
     * @dev Each user claims based on TGE + cycle logic if tgePercent > 0.
     *      If tgePercent == 0, they can claim entire allocation at once. 
     */
       function claim() external nonReentrant {
        require(airdrop.isLive, "Airdrop not live or cancelled");
        uint256 userAllocation = Allocations[msg.sender];
        require(userAllocation > 0, "No allocation");
        // If tgePercent == 0, there's no vesting schedule => claim everything
        if (airdrop.tgePercent == 0) {
            // The user claims all at once
            Allocations[msg.sender] = 0;
            // Increase totalDistributed 
           airdrop.totalDistributed = airdrop.totalDistributed.add(userAllocation);
            // Transfer
           tokenAddress.safeTransfer(msg.sender, userAllocation);

           claimed[msg.sender]=userAllocation;
        } else {
            // Vesting logic: calculate how many tokens are unlocked for the user
            uint256 unlocked = _unlockedTokens(msg.sender);
            require(unlocked > 0, "Nothing unlocked yet");
            // Increase claimed
            claimed[msg.sender] = claimed[msg.sender].add(unlocked);
            // Increase totalDistributed
            airdrop.totalDistributed = airdrop.totalDistributed.add(unlocked);
            // Transfer
            tokenAddress.safeTransfer(msg.sender, unlocked);
        }

        // If we've distributed all tokens, end the airdrop
        if (airdrop.totalDistributed >= airdrop.totalDistibution) {
            airdrop.isLive = false;
            emit AirdropEnded();
        }
    }


    // ------------------------------------------------
    // View Functions
    // ------------------------------------------------

    /**
     * @dev Returns how many tokens can be claimed right now by `user`.
     */
    function canClaimNow(address user) external view returns (uint256) {
        return _unlockedTokens(user);
    }

    /**
     * @dev Returns the next timestamp when `user` will have more tokens unlocked.
     *      If they can claim now or are fully vested, returns 0.
     */
    function nextClaimTime(address user) external view returns (uint256) {
        // 1. If airdrop not live or user has no allocation, or tgePercent == 0 => claim all anytime => 0
        if (!airdrop.isLive || Allocations[user] == 0 || airdrop.tgePercent == 0) {
            return 0;
        }

        // 2. If block.timestamp < airdrop.startTime => user must wait until startTime
        if (block.timestamp < airdrop.startTime) {
            return airdrop.startTime;
        }

        // 3. Check how many tokens are unlocked so far
        uint256 unlockedSoFar = _unlockedTokensSoFar(user); // total that should be unlocked (not subtracting claimed)
        uint256 userClaimed = claimed[user];

        // If user can claim something right now
        if (unlockedSoFar > userClaimed) {
            return 0; 
        }

        // If user is fully vested (unlockedSoFar == full allocation), no further unlock => 0
        if (unlockedSoFar == Allocations[user]) {
            return 0;
        }

        // Next cycle boundary
        // e.g. cyclesElapsed = floor((block.timestamp - startTime) / cycleTime)
        uint256 timeSinceStart = block.timestamp.sub(airdrop.startTime);
        uint256 cyclesElapsed = timeSinceStart.div(airdrop.cycleTime);
        uint256 nextCycle = cyclesElapsed.add(1); 
        uint256 nextCycleTimestamp = airdrop.startTime.add(nextCycle.mul(airdrop.cycleTime));

        return nextCycleTimestamp;
    }

    // ------------------------------------------------
    // Internal Logic
    // ------------------------------------------------

    /**
     * @dev Calculates how many tokens the user can claim RIGHT NOW (unlocked minus already claimed).
     */
    function _unlockedTokens(address user) internal view returns (uint256) {
        // If TGE hasn't started or no vesting, we handle that logic
        // but let's unify it with the next function:
      console.log("DATA1");
        uint256 totalUnlockedSoFar = _unlockedTokensSoFar(user);
        uint256 alreadyClaimed = claimed[user];

        if (totalUnlockedSoFar <= alreadyClaimed) {
                  console.log("DATA2");

            return 0;
        }

        return totalUnlockedSoFar.sub(alreadyClaimed);
    }

    /**
     * @dev Calculates how many tokens in total should be unlocked so far (without subtracting claimed).
     *      TGE + cycles, up to user's full allocation.
     */
    function _unlockedTokensSoFar(address user) internal view returns (uint256) {
        uint256 totalAlloc = Allocations[user];
              console.log("DATA3");

        if (totalAlloc == 0) {
                  console.log("DATA4");

            return 0;
        }
        // If TGE not started, 0
        if (block.timestamp < airdrop.startTime) {
                  console.log("DATA5");

            return 0;
        }
        // TGE portion
        uint256 tgePortion = totalAlloc.mul(airdrop.tgePercent).div(100);
        uint256 totalUnlockedSoFar = tgePortion;
              console.log("DATA6");

        // Cycles
        uint256 timeSinceTGE = block.timestamp.sub(airdrop.startTime);
        if (timeSinceTGE > 0 && airdrop.cycleTime > 0 && airdrop.cyclePercent > 0) {
                  console.log("DATA7");

            uint256 cyclesElapsed = timeSinceTGE.div(airdrop.cycleTime);
            uint256 cycleUnlockPerCycle = totalAlloc.mul(airdrop.cyclePercent).div(100);
            uint256 totalCycleUnlock = cycleUnlockPerCycle.mul(cyclesElapsed);
            totalUnlockedSoFar = totalUnlockedSoFar.add(totalCycleUnlock);
            // Cap at totalAlloc
            if (totalUnlockedSoFar > totalAlloc) {
                      console.log("DAT7");

                totalUnlockedSoFar = totalAlloc;
            }
        }
        return totalUnlockedSoFar;
    }
}
