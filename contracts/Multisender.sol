// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

 contract Multisender is Ownable{
    using SafeMath for uint256;
    using SafeMath for uint16;

    uint16 public recipentLimit;
    receive() external payable {

    }

constructor(){

}

    function SandEthEqaully (address payable [] calldata _address) external payable {
        uint16 length=uint16(_address.length);
        uint256 value=msg.value.div(length);
        for (uint16 i;i<length;++i){
            _address[i].transfer(value);
        }
    }

      function SendEthByValue (address payable [] calldata _address,uint256 [] calldata values ) external payable {
        uint16 length=uint16(_address.length);
        for (uint16 i;i<length;++i){
            _address[i].transfer(values[i]);
        }
    }

    function SandTokenEqaully (address _tokenAddress,address payable [] calldata _address, uint256 _amount) external  {
        uint16 length=uint16(_address.length);
        uint256 value=_amount.div(length);
        IERC20 tokenAddress=IERC20(_tokenAddress);
        for (uint16 i;i<length;++i){
            tokenAddress.transferFrom(msg.sender,_address[i],value);
        }
    }
     
     function SendTokenByValue (address _tokenAddress , address payable [] calldata _address,uint256 [] calldata values) external payable {
        uint16 length=uint16(_address.length);
        IERC20 tokenAddress=IERC20(_tokenAddress);
        for (uint16 i;i<length;++i){
            tokenAddress.transferFrom(msg.sender,_address[i],values[i]);
        }
    }
 //withdraw
    function withdraw(address payable  _address,uint256 _value) external onlyOwner{
        _address.transfer(_value);
    }
// withdraw 
   function withdrawTokens(address _tokenAddress,address _address, uint256 _value) external  onlyOwner{
    IERC20(_tokenAddress).transfer(_address,_value);
   }

 }
//  0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db
// 0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB