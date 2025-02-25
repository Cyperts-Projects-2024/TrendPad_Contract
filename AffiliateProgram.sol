// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

contract AffiliateProgram is Ownable {
    struct ReferralInfo {
        address referrer;
        uint256 totalReferredInvestment;
    }

    // Mapping: poolAddress => userAddress => ReferralInfo
    mapping(address => mapping(address => ReferralInfo)) public referrals;
    mapping(address => mapping(address => uint256)) public affiliateRewards; // Tracks rewards per referrer, per pool

    event Referred(address indexed pool, address indexed user, address indexed referrer, uint256 amount);
    event RewardDistributed(address indexed pool, address indexed referrer, uint256 rewardAmount);
    uint256 public rewardPercentage = 500; // 5% (500 / 10000)
    
    function setRewardPercentage(uint256 _percentage) external onlyOwner {
        require(_percentage <= 1000, "Cannot exceed 10%");
        rewardPercentage = _percentage;
    }

constructor() Ownable(msg.sender){

}
}