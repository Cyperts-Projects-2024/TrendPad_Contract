// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";


interface IAirdropPool {
    function initialize(address _tokenAddress, string memory _metaUrl) external;
    function transferOwnership(address newOwner) external;
}
contract AirdropFactoryV1 is Initializable, OwnableUpgradeable , UUPSUpgradeable {

    uint256 public platformfee;
    address public feeWallet;
    address public implementation; // Address of the AirdropPool implementation contract
    address[] public idoPools; //to Storing the all pool data 

    mapping(address => address[]) private userPools; //get the user pool
    event PoolCreated(address indexed poolAddress,address creater);
    event PlatformFeeUpdated(uint256 newFeeToken);
    event FeeWalletUpdated(address indexed _newFeeWallet);

     

    function initialize(
        uint256 _platformFee,
        address _feeWallet,
        address _implementation
    ) public initializer {
        __Ownable_init(msg.sender);
        platformfee = _platformFee;
        feeWallet = _feeWallet;                                         
        implementation = _implementation;
    } 
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getIdoPools() public view returns(address[] memory){
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

     function createAirdrop(
        ERC20 _tokenAddress,
        string memory _metaUrl
    ) external payable returns (address) {
     require(msg.value >= platformfee, "Insufficient fee sent");
     require(address(_tokenAddress) != address(0), "token address can't be zero");
     require(address(_tokenAddress).code.length > 0, "Invalid token address"); 
     address clone = Clones.clone(implementation);
     IAirdropPool(clone).initialize(address(_tokenAddress), _metaUrl);
     IAirdropPool(clone).transferOwnership(msg.sender);
    idoPools.push(address(clone));
        
        userPools[msg.sender].push(address(clone));

        (bool success, ) = payable(feeWallet).call{value: msg.value}("");
        require(success, "Fee transfer failed");
        emit PoolCreated(address(clone), msg.sender);
        return address(clone);
    }

    function getUserPools(address _user) external view returns(address[] memory) {
        return userPools[_user];
    }

    function getPlatformFee() external view returns(uint256) {
        return platformfee;
    }

    function getFeeWallet() external view returns(address) {
        return feeWallet;
    }
    
    function getImplementation() external view returns(address) {
        return implementation;
    }

    function setImplementation(address _implementation) external onlyOwner {
        require(_implementation != address(0), "Invalid implementation address");
        implementation = _implementation;
    }

}