// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./SafeMath.sol";

interface ITrendFairLaunchPool {
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

    struct BuyBackInfo {
        uint8 buybackPercentage;
        address buyBackMangerAddrress;
    }

    function initialize(
        SaleInfo memory _saleInfo,
        Timestamps memory _timestamps,
        DEXInfo memory _dexInfo,
        address _locker,
        address _feeWallet,
        uint256 _feeAmount
    ) external;

    function setVesting(VestingInfo memory _vestingInfo) external;

    function transferOwnership(address newOwner) external;

    function setBuyBack(BuyBackInfo memory _buyBackInfo) external;

    function enableAffilate(bool _enable, uint8 _affiliateRate) external;
}

interface IBuyBackManager {
    function getBuyBackDefaultInfo()
        external
        view
        returns (
            uint256 _amountPerBuyBack,
            uint256 _minBuyBackDeley,
            uint256 _maxBuyBackDeley
        );

    function setBuybackConfig(
            address _pool,
            address _tokenAAddress,
            address _tokenBAddress,
            address _routerAddress,
            uint8 _percentage,
            uint256 _totalBuyBackAmount,
            bool isNativeStatus
        ) external ;
}

contract TrendPadIDOFairLaunchFactoryV2 is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for ERC20;
    using SafeMath for uint256;
    address public feeWallet;
    uint256 public feePercent;
    address public fairLaunchTrendPoolImplementation;
    address public fairLaunchERC20TrendPoolImplementation;
    uint256 public platformFee;
    address public buyBackManagerAddress; // Address of the buyback manager contract

    address[] public TrendPools; //to Storing the all pool data
    mapping(address => address[]) private userPools; //get the user pool

    event IDOCreated(
        address indexed owner,
        address TrendPool,
        address indexed rewardToken
    );

    event feePercentUpdated(uint256 newfeePercent);
    event FeeWalletUpdated(address newFeeWallet);

    function initialize(
        uint256 _feePercent,
        address _feeWallet,
        uint256 _platformFee,
        address _fairLaunchPoolAddress,
        address _fairLaunchERC20PoolAddress,
        address _buyBackManagerAddress
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        feeWallet = _feeWallet;
        feePercent = _feePercent;
        platformFee = _platformFee;
        fairLaunchTrendPoolImplementation = _fairLaunchPoolAddress;
        fairLaunchERC20TrendPoolImplementation = _fairLaunchERC20PoolAddress;
        buyBackManagerAddress = _buyBackManagerAddress;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

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

    function setBuyBackManagerAddress(
        address _buyBackManagerAddress
    ) external onlyOwner {
        require(_buyBackManagerAddress != address(0), "Invalid address");
        buyBackManagerAddress = _buyBackManagerAddress;
    }

    function setTrendPoolImplementation(
        address _implementation
    ) external onlyOwner {
        require(_implementation != address(0), "Invalid implementation");
        fairLaunchTrendPoolImplementation = _implementation;
    }

    function setTrendERC20PoolImplementation(
        address _implementation
    ) external onlyOwner {
        require(_implementation != address(0), "Invalid implementation");
        fairLaunchERC20TrendPoolImplementation = _implementation;
    }

    function setPlatformFee(uint256 _platformFee) external onlyOwner {
        require(_platformFee > 0, "Platform fee must be greater than zero");
        platformFee = _platformFee;
    }

    function processIDOCreate(
        uint256 transferAmount,
        ERC20 _saleToken,
        address TrendPoolAddress
    ) private {
        _saleToken.safeTransferFrom(
            msg.sender,
            TrendPoolAddress,
            transferAmount
        );

        TrendPools.push(TrendPoolAddress);
        userPools[msg.sender].push(TrendPoolAddress);
        emit IDOCreated(msg.sender, TrendPoolAddress, address(_saleToken));
    }

    function createFairLaunch(
        ITrendFairLaunchPool.SaleInfo memory _saleInfo,
        ITrendFairLaunchPool.Timestamps memory _timestamps,
        ITrendFairLaunchPool.DEXInfo memory _dexInfo,
        ITrendFairLaunchPool.VestingInfo memory _vestingInfo,
        address _lokerFactoryAddress,
        uint8 _affiliateRate,
        uint8 _buyBackPercent
    ) external payable {
        require(
            fairLaunchTrendPoolImplementation != address(0),
            "Implementation not set"
        );
        require(msg.value >= platformFee, "Insufficient platform fee Paid");
        require(
            _saleInfo.saleToken != address(0),
            "Sale token address cannot be zero"
        );
        require(
            _timestamps.startTimestamp < _timestamps.endTimestamp,
            "Start Time Must be less than End Time"
        );
        require(
            _timestamps.endTimestamp > block.timestamp,
            "End Time must be Greater than now"
        );
        require(
            _timestamps.unlockTime == 0 || _timestamps.unlockTime >= 600,
            "Unlock time must be greater than or equal 10 mins or 0 (no lock)"
        );

        require(
            _saleInfo.lpPercent >= 51 || _saleInfo.lpPercent == 0,
            "LP% must be greater than 51%"
        );

        // Transfer platform fee to feeWallet
       _safeTransferETH(feeWallet, platformFee);
        
        if (_saleInfo.lpPercent > 0) {
            require(
                _dexInfo.router != address(0),
                "Router address required for auto-listing"
            );
            require(
                _dexInfo.factory != address(0),
                "Factory address required for auto-listing"
            );
            require(
                _dexInfo.weth != address(0),
                "WETH address required for auto-listing"
            );
        }

        bytes memory initData = abi.encodeWithSelector(
            ITrendFairLaunchPool.initialize.selector,
            _saleInfo,
            _timestamps,
            _dexInfo,
            _lokerFactoryAddress,
            feeWallet,
            feePercent
        );
        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            fairLaunchTrendPoolImplementation,
            initData
        );
        address fairLaunchTrendPoolProxy = address(proxy);
        uint256 saleTokenAmount = _saleInfo.tokenAmount;

        if (_saleInfo.lpPercent > 0) {
            saleTokenAmount = saleTokenAmount.add(
                getFairLaunchTokenAmount(
                    saleTokenAmount,
                    _saleInfo.lpPercent,
                    18
                )
            );
        }
        //set buyBack
        if (_saleInfo.isBuyBackEnabled && _buyBackPercent > 0) {
            require(
                _saleInfo.lpPercent.add(_buyBackPercent) <= 100 &&
                    _saleInfo.lpPercent.add(_buyBackPercent) >= 51,
                "LP and buyback percent must be Less than and equal 100 and greater than 51"
            );
            require(
                buyBackManagerAddress != address(0),
                "Buyback manager address not set"
            );
            uint256 calulatedAmount = (_saleInfo.softCap * _buyBackPercent) /100;
            IBuyBackManager(buyBackManagerAddress).setBuybackConfig(
                fairLaunchTrendPoolProxy,
                _saleInfo.saleToken,
                _dexInfo.weth,
                _dexInfo.router,
                _buyBackPercent,
                calulatedAmount,
                true
            );

            // update the buyback info in the pool contract
            ITrendFairLaunchPool(fairLaunchTrendPoolProxy).setBuyBack(
                ITrendFairLaunchPool.BuyBackInfo({
                    buybackPercentage: _buyBackPercent,
                    buyBackMangerAddrress: buyBackManagerAddress
                })
            );
        }
        // if select the vesting so set the vesting info in the pool contract
        if (_saleInfo.isVestingEnabled) {
            ITrendFairLaunchPool(fairLaunchTrendPoolProxy).setVesting(
                _vestingInfo
            );
        }

        if (_saleInfo.isAffiliatationEnabled) {
            ITrendFairLaunchPool(fairLaunchTrendPoolProxy).enableAffilate(
                true,
                _affiliateRate
            );
        }

        ITrendFairLaunchPool(fairLaunchTrendPoolProxy).transferOwnership(
            msg.sender
        );
        processIDOCreate(
            saleTokenAmount,
            ERC20(_saleInfo.saleToken),
            fairLaunchTrendPoolProxy
        );
    }

    function createFairLaunchERC20(
        ITrendFairLaunchPool.SaleInfo memory _saleInfo,
        ITrendFairLaunchPool.Timestamps memory _timestamps,
        ITrendFairLaunchPool.DEXInfo memory _dexInfo,
        ITrendFairLaunchPool.VestingInfo memory _vestingInfo,
        address _lokerFactoryAddress,
        uint8 _affiliateRate,
        uint8 _buyBackPercent
    ) external payable {
        require(
            fairLaunchERC20TrendPoolImplementation != address(0),
            "Implementation not set"
        );
        require(msg.value >= platformFee, "Insufficient platform fee");
    
        require(
            _saleInfo.saleToken != address(0),
            "Sale token address cannot be zero"
        );
        require(
            _saleInfo.currency != address(0),
            "Currency address cannot be zero"
        );
        require(
            _timestamps.startTimestamp < _timestamps.endTimestamp,
            "Start Time Must be less than End Time"
        );
        require(
            _timestamps.endTimestamp > block.timestamp,
            "End Time must be Greater than now"
        );
        require(
            _timestamps.unlockTime == 0 || _timestamps.unlockTime >= 600,
            "Unlock time must be greater than or equal 10 mins "
        );
        require(
            _saleInfo.lpPercent >= 51 || _saleInfo.lpPercent == 0,
            "LP% must be greater than 51%"
        );
    
      _safeTransferETH(feeWallet, platformFee);
    
        if (_saleInfo.lpPercent > 0) {
            require(
                _dexInfo.router != address(0),
                "Router address required for auto-listing"
            );
            require(
                _dexInfo.factory != address(0),
                "Factory address required for auto-listing"
            );
            require(
                _dexInfo.weth != address(0),
                "WETH address required for auto-listing"
            );
        }
        bytes memory initData = abi.encodeWithSelector(
            ITrendFairLaunchPool.initialize.selector,
            _saleInfo,
            _timestamps,
            _dexInfo,
            _lokerFactoryAddress,
            feeWallet,
            feePercent
        );
        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            fairLaunchERC20TrendPoolImplementation,
            initData
        );
        address fairLaunchTrendPoolProxy = address(proxy);
        uint8 decimals = ERC20(_saleInfo.currency).decimals();
        uint256 saleTokenAmount = _saleInfo.tokenAmount;
        if (_saleInfo.lpPercent > 0) {
            saleTokenAmount = saleTokenAmount.add(
                getFairLaunchTokenAmount(
                    saleTokenAmount,
                    _saleInfo.lpPercent,
                    decimals
                )
            );
        }
        //set buyBack
        if (_saleInfo.isBuyBackEnabled && _buyBackPercent > 0) {
            require(
                _saleInfo.lpPercent.add(_buyBackPercent) <= 100 &&
                    _saleInfo.lpPercent.add(_buyBackPercent) >= 51,
                "LP and buyback percent must be Less than and equal 100 and greater than 51"
            );
            require(
                buyBackManagerAddress != address(0),
                "Buyback manager address not set"
            );
            uint256 calulatedAmount = (_saleInfo.softCap * _buyBackPercent) /
                100;
            IBuyBackManager(buyBackManagerAddress).setBuybackConfig(
                fairLaunchTrendPoolProxy,
                _saleInfo.saleToken,
                _saleInfo.currency,
                _dexInfo.router,
                _buyBackPercent,
                calulatedAmount,
                false
            );
            // update the buyback info in the pool contract
            ITrendFairLaunchPool(fairLaunchTrendPoolProxy).setBuyBack(
                ITrendFairLaunchPool.BuyBackInfo({
                    buybackPercentage: _buyBackPercent,
                    buyBackMangerAddrress: buyBackManagerAddress
                })
            );
        }
        // if select the vesting so set the vesting info in the pool contract
        if (_saleInfo.isVestingEnabled) {
            ITrendFairLaunchPool(fairLaunchTrendPoolProxy).setVesting(
                _vestingInfo
            );
        }

        if (_saleInfo.isAffiliatationEnabled) {
        ITrendFairLaunchPool(fairLaunchTrendPoolProxy).enableAffilate(
                true,
                _affiliateRate
            );
        }

        ITrendFairLaunchPool(fairLaunchTrendPoolProxy).transferOwnership(
            msg.sender
        );
        // Process the IDO creation
        processIDOCreate(
            saleTokenAmount,
            ERC20(_saleInfo.saleToken),
            fairLaunchTrendPoolProxy
        );
    }

    function getFairLaunchTokenAmount(
        uint256 _amount,
        uint lpPercent,
        uint8 decimals
    ) public view returns (uint256) {
        uint ethAmount= 1 * 10** decimals; // 1 ETH in wei
        uint256 fee = (ethAmount * feePercent) / 100; // Calculate fee
        uint256 adjustedEthAmount = ethAmount - fee; // Adjust ETH amount after fee
        uint256 lpAdjusted = (adjustedEthAmount * lpPercent) / 100; // Adjust by lpPercent
        uint256 finalAmount = (lpAdjusted * _amount) / (10 ** decimals); // Final amount
        return finalAmount;
    }

    function getUserPools(
        address _user
    ) public view returns (address[] memory) {
        return userPools[_user];
    }

    function getBuyBackManagerAddress() public view returns (address) {
        return buyBackManagerAddress;
    }

    function getFeeWallet() public view returns (address) {
        return feeWallet;
    }

    function getFeePercent() public view returns (uint256) {
        return feePercent;
    }

    function getFairLaunchTrendPoolImplementation()
        public
        view
        returns (address)
    {
        return fairLaunchTrendPoolImplementation;
    }

    function getTrendPoolsCount() public view returns (uint256) {
        return TrendPools.length;
    }

    function getUserPoolCount(address _user) public view returns (uint256) {
        return userPools[_user].length;
    }

    function _safeTransferETH(address to, uint256 amount) internal {
    bool success;
    assembly {
        success := call(gas(), to, amount, 0, 0, 0, 0)
    }
    require(success, "ETH transfer failed"); 
  }

    function isContract(address _addr) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }
}
