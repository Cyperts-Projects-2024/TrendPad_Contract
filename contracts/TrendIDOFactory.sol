// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface ITrendPool {
   struct SaleInfo {
                address Currency ;
                address rewardToken;
                uint256 presaleToken;
                uint256 liquidityToken;
                uint256 tokenPrice;           // Price per token in WEI
                uint256 softCap;              // Min ETH required
                uint256 hardCap;              // Max ETH raised
                uint256 minEthPayment;        // Min contribution
                uint256 maxEthPayment;        // Max contribution
                uint256 listingPrice;         // (Optional) listing price in WEI
                uint256 lpInterestRate;       // (Optional) % of raised ETH for LP
                bool  burnType;
                bool affiliation; 
                bool isEnableWhiteList ; 
                bool isVestingEnabled;// (Unused flag; we do actual affiliate logic below)
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

    struct VestingInfo {
            uint8 TGEPercent;
            uint256 cycleTime;
            uint8 releasePercent;
            uint256 startTime;
    }

    struct AffiliateInfo {             
        uint8 poolRefCount;            // Total number of users referred
        uint8 realTimeRewardPercentage;// Current reward % based on referrals
        uint256 currentReward;           // Current reward user can claim
        uint256 maxReward;               // Max reward user can earn
        uint256 totalReferredAmount; // Total amount referred by user
        uint256 totalRewardAmount;    
    }
    
    function initialize(
        SaleInfo memory _saleInfo,
        Timestamps memory _timestamps,
        DEXInfo memory _dexInfo,
        address _locker,
        address _feeWallet,
        uint8 _feePercent
    ) external;

    function transferOwnership(address newOwner) external;

    function setVestingInfo(
        VestingInfo memory _vestingInfo
    ) external
    ;

    function enableAffilate(bool _enabled, uint8 _rate) external; 

}

interface  ITrendERC20Pool{

    struct SaleInfo {
        address Currency; 
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
        bool affiliation; 
        bool isEnableWhiteList ;    // (Unused flag; we do actual affiliate logic below)
        bool isVestingEnabled;
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
            uint256 totalInvested;
            bool isRefunded; // Used to track if user has withdrawn their contribution
        }

    struct AffiliateInfo {             
        uint8 poolRefCount;            // Total number of users referred
        uint8 realTimeRewardPercentage;// Current reward % based on referrals
        uint256 currentReward;           // Current reward user can claim
        uint256 maxReward;               // Max reward user can earn
        uint256 totalReferredAmount; // Total amount referred by user
        uint256 totalRewardAmount;    
    }

    struct VestingInfo {
            uint8 TGEPercent;
            uint256 cycleTime;
            uint8 releasePercent;
            uint256 startTime;
    }

    function initialize (
        SaleInfo memory _saleInfo,
        Timestamps memory _timestamps,
        DEXInfo memory _dexInfo,
        address _locker,
        address _feeWallet,
        uint8 _feePercent
    )external;
    
    function setVestingInfo(VestingInfo memory _vestingInfo) external;
    function enableAffilate(bool _enabled, uint8 _rate) external ; 

function transferOwnership(address newOwner) external;
}

contract TrendPadIDOFactoryV3 is Initializable ,OwnableUpgradeable ,UUPSUpgradeable{
    using SafeERC20 for ERC20;

    address public feeWallet;
    uint256 public feePercent;
    address[] public TrendPools; 
    mapping(address => address[]) private userPools; 
    
    event IDOCreated(
        address indexed owner,
        address TrendPool,
        address indexed rewardToken);

    event feePercentUpdated(uint256 newfeePercent);
    event FeeWalletUpdated(address newFeeWallet);

    address public trendPoolImplementation;
    address public trendERC20PoolImplementation;
    /// @custom:oz-renamed-from x

    uint256 public platformFee;

    function initialize(uint256 _feePercent, address _feeWallet,uint256 _platformFee , address _trendPool, address _trendERCPool) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        feeWallet = _feeWallet;
        feePercent = _feePercent;
        platformFee = _platformFee;
        trendPoolImplementation = _trendPool;
        trendERC20PoolImplementation = _trendERCPool;
    }
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getTrendPools() public view returns (address[] memory) {
      return TrendPools;
    }

    function setFeePercent(uint256 _newfeePercent) external onlyOwner {
        feePercent = _newfeePercent;
        emit feePercentUpdated(_newfeePercent);
    }
    
    function setFeeWallet(address _newFeeWallet) external onlyOwner {
        feeWallet = _newFeeWallet;
        emit FeeWalletUpdated(_newFeeWallet);
    }

    function setTrendPoolImplementation(address _implementation) external onlyOwner {
    require(_implementation != address(0), "Invalid implementation");
    trendPoolImplementation = _implementation;
   }   

   function setTrendERC20PoolImplementation(address _implementation) external onlyOwner {
    require(_implementation != address(0), "Invalid implementation");
    trendERC20PoolImplementation = _implementation;
    }
    
  function setPlatformFee(uint256 _platformFee) external onlyOwner {
        require(_platformFee > 0, "Platform fee must be greater than 0");
        platformFee = _platformFee;
    }
    function processIDOCreate(
        uint256 transferAmount,
        ERC20 _rewardToken,
        address TrendPoolAddress
    ) private {
        _rewardToken.safeTransferFrom(
            msg.sender,
            TrendPoolAddress,
            transferAmount
        );
        
        TrendPools.push(TrendPoolAddress);
        userPools[msg.sender].push(TrendPoolAddress);
        emit IDOCreated(
            msg.sender,
            TrendPoolAddress,
            address(_rewardToken)
        );
    }
//for Native  token 
   function createIDO(
    ITrendPool.SaleInfo memory _finInfo,
    ITrendPool.Timestamps memory _timestamps,
    ITrendPool.DEXInfo memory _dexInfo,
    ITrendPool.VestingInfo memory _vestingInfo,
    address _lockerFactoryAddress,
    uint8  _affiliateRate
) payable external {
    require(trendPoolImplementation != address(0), "Implementation not set");
    require(msg.value >= platformFee, "Platform fee not paid");

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

    require(
            _finInfo.softCap <= _finInfo.hardCap &&
            (_finInfo.hardCap * 25) / 100 <= _finInfo.softCap,
            "SoftCap must be >= 25% of HardCap"
        );

    require(_finInfo.lpInterestRate >= 51 || _finInfo.lpInterestRate==0, "LP% must be >= 51%");
    
        // Transfer platform fee to feeWallet
    payable(feeWallet).transfer(platformFee);

    // Prepare encoded initializer call
    bytes memory initData = abi.encodeWithSelector(
        ITrendPool.initialize.selector,
        _finInfo,
        _timestamps,
        _dexInfo,
        _lockerFactoryAddress,
        feeWallet,
        feePercent
    );
    // Deploy proxy
    ERC1967Proxy proxy = new ERC1967Proxy(trendPoolImplementation, initData);
    address trendPoolProxy = address(proxy);
    uint8 formateUnit = 18;
    uint256 transferAmount = getTokenAmount(
        _finInfo.hardCap,
        _finInfo.tokenPrice,
        formateUnit
    );
    
    if (_finInfo.lpInterestRate > 0 && _finInfo.listingPrice > 0) {
        // uint256 feeAmount=(_finInfo.hardCap * feePercent)/100;
        transferAmount += getTokenAmount(
            ((_finInfo.hardCap) * _finInfo.lpInterestRate) / 100,
            _finInfo.listingPrice,
            formateUnit
        );
    }

    if(_finInfo.affiliation)
    {
            ITrendPool(trendPoolProxy).enableAffilate(
                 true,
                _affiliateRate
            );
    }
    // if select the vesting so set the vesting info in the pool contract
    if(_finInfo.isVestingEnabled) {
        ITrendPool(trendPoolProxy).setVestingInfo(_vestingInfo);
    }

    ITrendPool(trendPoolProxy).transferOwnership(msg.sender);

    // Proceed with reward token transfer and registration
    processIDOCreate(
        transferAmount,
       ERC20( _finInfo.rewardToken),
        trendPoolProxy
    );
}

    // for Erc-20 To
    function createIDOERC20(
        ITrendERC20Pool.SaleInfo memory _finInfo,
        ITrendERC20Pool.Timestamps memory _timestamps,
        ITrendERC20Pool.DEXInfo memory _dexInfo,
        ITrendERC20Pool.VestingInfo memory _vestingInfo,
         address _lockerFactoryAddress,
        uint8 _affiliateRate
    ) payable external {
      
        require(trendERC20PoolImplementation != address(0), "Implementation not set");
        require(msg.value >= platformFee, "Platform fee not paid");

        require(
                _finInfo.Currency != address(0),
                "Currency address cannot be zero"
        );
        require(
                _timestamps.startTimestamp < _timestamps.endTimestamp,
                "Start < End required"
        );
        require(
                _timestamps.endTimestamp > block.timestamp,
                "End must be > now"
        );
        require
              (_finInfo.lpInterestRate ==0 && _timestamps.unlockTime == 0 || _timestamps.unlockTime >=51 &&_timestamps.unlockTime >= 600,
                "Unlock time must be >= 10 mins "
        );
        require(_finInfo.lpInterestRate >= 51 || _finInfo.lpInterestRate==0, "LP% must be >= 51%");
        require(
                _finInfo.softCap <= _finInfo.hardCap &&
                (_finInfo.hardCap * 25) / 100 <= _finInfo.softCap,
                "SoftCap must be >= 25% of HardCap"
        );

            // Transfer platform fee to feeWallet
        payable(feeWallet).transfer(platformFee);

        
        bytes memory initData = abi.encodeWithSelector(
        ITrendERC20Pool.initialize.selector,
        _finInfo,
        _timestamps,
        _dexInfo,   
        _lockerFactoryAddress,
        feeWallet,
        feePercent
        );
        ERC1967Proxy proxy = new ERC1967Proxy(trendERC20PoolImplementation, initData);
        address trendERC20PoolProxy = address(proxy);
        uint8 formateUnit = ERC20(_finInfo.Currency).decimals();
        uint256 transferAmount = getTokenAmount(_finInfo.hardCap, _finInfo.tokenPrice, formateUnit);

    if (_finInfo.lpInterestRate > 0 && _finInfo.listingPrice > 0) {
            transferAmount += getTokenAmount((_finInfo.hardCap * _finInfo.lpInterestRate) / 100, _finInfo.listingPrice, formateUnit);
    }
        
    if(_finInfo.affiliation)
    {
            ITrendERC20Pool(trendERC20PoolProxy).enableAffilate(
                 true,
                _affiliateRate
            );
    }

    if(_finInfo.isVestingEnabled) {
            ITrendERC20Pool(trendERC20PoolProxy).setVestingInfo(_vestingInfo);
    }

    ITrendERC20Pool(trendERC20PoolProxy).transferOwnership(msg.sender);

    processIDOCreate(
            transferAmount,
            ERC20(_finInfo.rewardToken),
            address(trendERC20PoolProxy)
        );
    }
   
    function getTokenAmount(uint256 ethAmount, uint256 oneTokenInWei, uint8 decimals)
        public 
        pure
        returns (uint256)
    {
        return (ethAmount * oneTokenInWei) / 10**decimals;
    }

    function getUserPools(address _user) public view returns (address[] memory) {
        return userPools[_user];
    }
    
    function getUserPoolCount(address _user) public view returns (uint256) {
        return userPools[_user].length;
    }

  
}
