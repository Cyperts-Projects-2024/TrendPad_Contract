// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "./TrendPool.sol";
import "./TrendERC20Pool.sol";
import "./Fairlaunch.sol";
import "./FairLaunchToken.sol";

contract IDOFactory is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20Burnable;
    using SafeERC20 for ERC20;

    ERC20Burnable public feeToken;
    address public feeWallet;
    uint256 public feePercent;
   
    address[] public TrendPools; //to Storing the all pool data 
    mapping(address => address[]) private userPools; //get the user pool

    mapping (address => bool) public TrendPoolsMap;

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
        ERC20Burnable _feeToken,
        uint256 _feePercent,
        uint256 _burnPercent
    )Ownable(msg.sender){
        feeToken = _feeToken;
        feePercent = _feePercent;
    }

    function isIdoAddress(address _address) public view returns (bool) {
        return TrendPoolsMap[_address];
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
        TrendPool TrendPool =
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
       TrendPool.transferOwnership(msg.sender);
        uint8 tokenDecimals = _rewardToken.decimals();

        uint256 transferAmount = getTokenAmount(_finInfo.hardCap, _finInfo.tokenPrice, tokenDecimals);

        if (_finInfo.lpInterestRate > feePercent && _finInfo.listingPrice > 0) {
            transferAmount += getTokenAmount(_finInfo.hardCap * _finInfo.lpInterestRate / 100, _finInfo.listingPrice, tokenDecimals);
        }

       processIDOCreate(
            transferAmount,
            _rewardToken,
            address(TrendPool),
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
      
        TrendERC20Pool TrendPool =
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
        TrendPool.transferOwnership(msg.sender);

        processIDOCreate(
            transferAmount,
            _rewardToken,
            address(TrendPool),
            _metadataURL
        );
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
function createFairLaunch(
        ERC20 _saleTokenAddress,
        Fairlaunch.SaleInfo memory _saleInfo,
        Fairlaunch.Timestamps memory _timestamps,
        Fairlaunch.DEXInfo memory _dexInfo,
        address _localFactoryAddress,
        string memory _metadataURL
)
external {
    Fairlaunch fairLaunch=
            new Fairlaunch(
                _saleTokenAddress,
                _saleInfo,
                _timestamps,
                _dexInfo,
                _localFactoryAddress,
                feeWallet,
                feePercent
    );
    fairLaunch.transferOwnership(msg.sender);
    uint8 tokenDecimals = _saleTokenAddress.decimals();
    uint256 saleTokenAmount = _saleInfo.tokenAmount;
    if(_saleInfo.lpPayPercent > 0){
        saleTokenAmount = saleTokenAmount.add(getFairLaunchTokenAmount(saleTokenAmount,_saleInfo.lpPayPercent,tokenDecimals));
    }

    processIDOCreate(
        saleTokenAmount,
        _saleTokenAddress,
        address(fairLaunch),
        _metadataURL
    );
}

function createFairLaunchToken(    
        ERC20 _saleToken,
        ERC20 _payToken,
        FairLaunchToken.SaleInfo memory _saleInfo,
        FairLaunchToken.DexInfo memory _dexInfo,
        address _lockerAddress,
        FairLaunchToken.Timestamps memory _timestamps,
        string memory _metadataURL
)
external {
    FairLaunchToken fairLaunchToken=
            new FairLaunchToken(
                _saleToken,
                _payToken,
                _saleInfo,
                _timestamps,
                _dexInfo,
                _lockerAddress,
                _metadataURL,
                feeWallet,
                feePercent
    );
    fairLaunchToken.transferOwnership(msg.sender);
    uint8 saleTokenDecimals = _saleToken.decimals();
    uint8 payTokenDecimals = _payToken.decimals(); 
    uint256 saleTokenAmount = _saleInfo.tokenAmount; 
    if(_saleInfo.lpPercentage > 0){
        saleTokenAmount = saleTokenAmount.add(getFairLaunchTokenAmount(saleTokenAmount,_saleInfo.lpPercentage,saleTokenDecimals));
    }

    processIDOCreate(
        saleTokenAmount,
        _saleToken,
        address(fairLaunchToken),
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

    function getUserPools(address _user) public view returns (address[] memory) {
        return userPools[_user];
    }
    
    function getUserPoolCount(address _user) public view returns (uint256) {
        return userPools[_user].length;
    }
    function isContract(address _addr) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

}