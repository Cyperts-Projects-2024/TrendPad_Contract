// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import  "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "./AirdropPool.sol";
contract AirdropFactory is Ownable{

    uint256 public platformfee;
    address public feeWallet;
    address[] public idoPools; //to Storing the all pool data 
    mapping(address => address[]) private userPools; //get the user pool
   
    event PoolCreated(address indexed poolAddress,address creater);
    event PlatformFeeUpdated(uint256 newFeeToken);
    event FeeWalletUpdated(address indexed _newFeeWallet);

    constructor(uint256 _platformFee,address _feeWallet)Ownable(msg.sender){
      platformfee=_platformFee;
      feeWallet=_feeWallet;
    }

    function fetIdoPools() public view returns(address[] memory){
        return  idoPools;
    }

    function setPlatformFee(uint256 _newFeeAmount) external onlyOwner{
        platformfee=_newFeeAmount;
        emit PlatformFeeUpdated(_newFeeAmount);
    }
  
    function setFeeWallet(address _newFeeWallet) external onlyOwner {
        feeWallet = _newFeeWallet;
        emit FeeWalletUpdated(_newFeeWallet);
    }

    function createAirdrop(ERC20 _tokenAddress,address _createrAddress,string memory _metaUrl) external {
        AirdropPool airdropAdresss=  new AirdropPool(_tokenAddress,_createrAddress,_metaUrl);
        airdropAdresss.transferOwnership(msg.sender);
        idoPools.push(address(airdropAdresss));
        userPools[msg.sender].push(address(airdropAdresss));
        emit PoolCreated(address(_tokenAddress),_createrAddress);
   }

}