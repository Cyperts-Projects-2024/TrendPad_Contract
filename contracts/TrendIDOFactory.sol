// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./TrendPool.sol";
import "./TrendERC20Pool.sol";


contract IDOFactory is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    address public feeWallet;
    uint256 public feePercent;
   
    address[] public TrendPools; //to Storing the all pool data 
    mapping(address => address[]) private userPools; //get the user pool

    event IDOCreated(
        address indexed owner,
        address TrendPool,
        address indexed rewardToken,
        string tokenURI
    );

    event TokenFeeUpdated(address newFeeToken);
    event feePercentUpdated(uint256 newfeePercent);
    event FeeWalletUpdated(address newFeeWallet);

    constructor(
        uint256 _feePercent,
        address _feeWallet
    ){
       feeWallet  = _feeWallet;
        feePercent = _feePercent;
    }


    function getTrendPools() public view returns (address[] memory) {
      return TrendPools;
    }

    function setfeePercent(uint256 _newfeePercent) external onlyOwner {
        feePercent = _newfeePercent;
        emit feePercentUpdated(_newfeePercent);
    }
    
    function setFeeWallet(address _newFeeWallet) external onlyOwner {
        feeWallet = _newFeeWallet;
        emit FeeWalletUpdated(_newFeeWallet);
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
        ERC20 _rewardToken,
        TrendPool.SaleInfo memory _finInfo,
        TrendPool.Timestamps memory _timestamps,
        TrendPool.DEXInfo memory _dexInfo,
        address _lockerFactoryAddress,
        string memory _metadataURL,
        bool _burnType
    ) external {
        TrendPool trendPoolInstance =
            new TrendPool(
                _rewardToken,
                _finInfo,
                _timestamps,
                _dexInfo,
                _lockerFactoryAddress,
                _metadataURL,
                _burnType,
                feeWallet,
                feePercent
            );
       trendPoolInstance.transferOwnership(msg.sender);
        uint8 tokenDecimals = _rewardToken.decimals();

        uint256 transferAmount = getTokenAmount(_finInfo.hardCap, _finInfo.tokenPrice, tokenDecimals);
        if (_finInfo.lpInterestRate > feePercent && _finInfo.listingPrice > 0) {
            transferAmount += getTokenAmount(_finInfo.hardCap * _finInfo.lpInterestRate / 100, _finInfo.listingPrice, tokenDecimals);
        }

       processIDOCreate(
            transferAmount,
            _rewardToken,
            address(trendPoolInstance),
            _metadataURL
        );     
    }
    // for Erc-20 Token 
    function createIDOERC20(
        ERC20 _rewardToken,
        ERC20 _payToken,
        TrendERC20Pool.SaleInfo memory _finInfo,
        TrendERC20Pool.Timestamps memory _timestamps,
        TrendERC20Pool.DEXInfo memory _dexInfo,
         address _lockerFactoryAddress,
        string memory _metadataURL,
        bool _burnType
    ) external {
      
        TrendERC20Pool trendERC20PoolInstance =
            new TrendERC20Pool(
                _rewardToken,
                _payToken,
                _finInfo,
                _timestamps,
                _dexInfo,
                _lockerFactoryAddress,
                _metadataURL,
                _burnType,
                 feeWallet,
                 feePercent
            );
        uint8 rewardTokenDecimals = _rewardToken.decimals();
        uint256 transferAmount = getTokenAmount(_finInfo.hardCap, _finInfo.tokenPrice, rewardTokenDecimals);

    if (_finInfo.lpInterestRate > feePercent && _finInfo.listingPrice > 0) {
            transferAmount += getTokenAmount(_finInfo.hardCap * _finInfo.lpInterestRate / 100, _finInfo.listingPrice, rewardTokenDecimals);
        }
        trendERC20PoolInstance.transferOwnership(msg.sender);

        processIDOCreate(
            transferAmount,
            _rewardToken,
            address(trendERC20PoolInstance),
            _metadataURL
        );
    }

    function getTokenAmount(uint256 ethAmount, uint256 oneTokenInWei, uint8 decimals)
        internal
        pure
        returns (uint256)
    {
        return (ethAmount / oneTokenInWei) * 10**decimals;
    }

    function getUserPools(address _user) public view returns (address[] memory) {
        return userPools[_user];
    }
    
    function getUserPoolCount(address _user) public view returns (uint256) {
        return userPools[_user].length;
    }

   

}



// [800000000000000000000,100000000000000000,400000000000000000,100000000000000000,300000000000000000,500000000000000000000,51]
// [1735370216,1735370216,1735370216]
// 0xdD870fA1b7C4700F2BD7f44238821C26f7392148
// 4
// 0x57763c673527745678883f0564A4df9fC0C2d343    locking contract

// [1000000000000000000000,100000000000000000,0,51]
// 0xdD870fA1b7C4700F2BD7f44238821C26f7392148   9600000000000000000000
