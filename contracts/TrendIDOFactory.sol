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
                string metadataURL;
                bool affiliation; 
                bool isEnableWhiteList ;    // (Unused flag; we do actual affiliate logic below)
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


    function initialize(
        SaleInfo memory _saleInfo,
        Timestamps memory _timestamps,
        DEXInfo memory _dexInfo,
        address _locker,
        address _feeWallet,
        uint256 _feeAmount,
        uint8 _affiliateRate
    ) external;

    function transferOwnership(address newOwner) external;
}

contract TrendPadIDOFactoryV2 is Initializable ,OwnableUpgradeable ,UUPSUpgradeable{
    using SafeERC20 for ERC20;

    address public feeWallet;
    uint256 public feePercent;
    address[] public TrendPools; //to Storing the all pool data 
    mapping(address => address[]) private userPools; //get the user pool
    address public trendPoolImplementation;

    
    event IDOCreated(
        address indexed owner,
        address TrendPool,
        address indexed rewardToken,
        string tokenURI
    );

    event TokenFeeUpdated(address newFeeToken);
    event feePercentUpdated(uint256 newfeePercent);
    event FeeWalletUpdated(address newFeeWallet);

   
    function initialize(uint256 _feePercent, address _feeWallet) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        feeWallet = _feeWallet;
        feePercent = _feePercent;
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
    
        function processIDOCreate(
        uint256 transferAmount,
        ERC20 _rewardToken,
        address TrendPoolAddress,
        string memory _metadataURL
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
            address(_rewardToken),
            _metadataURL
        );
    }
//for Native  token 
   function createIDO(
    ITrendPool.SaleInfo memory _finInfo,
    ITrendPool.Timestamps memory _timestamps,
    ITrendPool.DEXInfo memory _dexInfo,
    address _lockerFactoryAddress,
    uint8  _affiliateRate,
    string memory _metadataURL
) external {
    require(trendPoolImplementation != address(0), "Implementation not set");
    // Prepare encoded initializer call
    bytes memory initData = abi.encodeWithSelector(
        ITrendPool.initialize.selector,
        _finInfo,
        _timestamps,
        _dexInfo,
        _lockerFactoryAddress,
        feeWallet,
        feePercent,
        _affiliateRate
    );
    // Deploy proxy
    ERC1967Proxy proxy = new ERC1967Proxy(trendPoolImplementation, initData);
    address trendPoolProxy = address(proxy);
    // Transfer ownership of the deployed pool to caller
    ITrendPool(trendPoolProxy).transferOwnership(msg.sender);
    // Calculate tokens to be transferred
    uint8 tokenDecimals = ERC20(_finInfo.rewardToken).decimals();
    uint256 transferAmount = getTokenAmount(
        _finInfo.hardCap,
        _finInfo.tokenPrice,
        tokenDecimals
    );
    
    if (_finInfo.lpInterestRate > 0 && _finInfo.listingPrice > 0) {
        transferAmount += getTokenAmount(
            _finInfo.hardCap * _finInfo.lpInterestRate / 100,
            _finInfo.listingPrice,
            tokenDecimals
        );
    }

    // Proceed with reward token transfer and registration
    processIDOCreate(
        transferAmount,
       ERC20( _finInfo.rewardToken),
        trendPoolProxy,
        _metadataURL
    );
}

    // for Erc-20 To
    //  function createIDOERC20(
    //     ERC20 _rewardToken,
    //     ERC20 _payToken,
    //     TrendERC20Pool.SaleInfo memory _finInfo,
    //     TrendERC20Pool.Timestamps memory _timestamps,
    //     TrendERC20Pool.DEXInfo memory _dexInfo,
    //      address _lockerFactoryAddress,
    //     string memory _metadataURL,
    //     bool _burnType
    // ) external {
      
    //     TrendERC20Pool trendERC20PoolInstance =
    //         new TrendERC20Pool(
    //             _rewardToken,
    //             _payToken,
    //             _finInfo,
    //             _timestamps,
    //             _dexInfo,
    //             _lockerFactoryAddress,
    //             _metadataURL,
    //             _burnType,
    //              feeWallet,
    //              feePercent
    //         );
    //     uint8 rewardTokenDecimals = _rewardToken.decimals();
    //     uint256 transferAmount = getTokenAmount(_finInfo.hardCap, _finInfo.tokenPrice, rewardTokenDecimals);

    // if (_finInfo.lpInterestRate > 0 && _finInfo.listingPrice > 0) {
    //         transferAmount += getTokenAmount(_finInfo.hardCap * _finInfo.lpInterestRate / 100, _finInfo.listingPrice, rewardTokenDecimals);
    //     }
    //     trendERC20PoolInstance.transferOwnership(msg.sender);

    //     processIDOCreate(
    //         transferAmount,
    //         _rewardToken,
    //         address(trendERC20PoolInstance),
    //         _metadataURL
    //     );
    // }
   
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
