// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AirdropPool is Ownable ,ReentrancyGuard{
    using SafeMath for uint256;
    using SafeERC20 for uint256;

    struct AirdropInfo{
        address tokenAddress;
        address createrAddress;
        string  metaurl;
    }

    constructor(ERC20 _tokenAddress,address _createrAddress,string memory _metaURl)Ownable(msg.sender){
    
    }
} 