// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ITrendMultisend {
    function multisendToken(
        address token,
        bool ensureExactAmount,
        address[] calldata targets,
        uint256[] calldata amounts
    ) external payable;

    function multisendEther(
        address[] calldata targets,
        uint256[] calldata amounts
    ) external payable;
}

contract TrendMultisend is Ownable, ITrendMultisend {
    using SafeERC20 for IERC20;
    uint256 public platformFee;
    address public feeWalletAddress;
    event Multisent(address token, uint256 total);

    receive() external payable {
        revert();
    }


    constructor(address initialOwner, uint256 _PlatformFee,address _feeWalletAddress) Ownable(initialOwner) {
        require(initialOwner != address(0), "Invalid owner address");
        require(_PlatformFee > 0, "Platform fee must be greater than zero");
        require(_feeWalletAddress != address(0), "Invalid fee wallet address");
        platformFee = _PlatformFee;
        feeWalletAddress = _feeWalletAddress;
    }

    function multisendToken(
        address token,
        bool ensureExactAmount,
        address[] calldata targets,
        uint256[] calldata amounts
    ) external payable override {
        require(
            msg.value >= platformFee,
            "Insufficient platform fee sent with the transaction"
        );
     
        // Transfer the platform fee to the fee wallet address
        (bool success, ) = feeWalletAddress.call{value: platformFee}("");
        require(success, "ETH transfer to fee wallet failed");


        if (token == address(0)) {
            multisendEther(targets, amounts);
        } else {
            require(targets.length == amounts.length, "Length mismatched");
            IERC20 erc20 = IERC20(token);
            uint256 total = 0;
            // In case people want to make sure they transfer the exact
            // amount of tokens to the recipients (for example, an owner
            // might forget excluding this contract from the transfer fee
            // deduction), use this option as a safeguard
            function(
                IERC20,
                address,
                address,
                uint256
            ) transfer = ensureExactAmount
                    ? _safeTransferFromEnsureExactAmount
                    : _safeTransferFrom;

            for (uint256 i = 0; i < targets.length; i++) {
                total += amounts[i];
                transfer(erc20, msg.sender, targets[i], amounts[i]);
            }

            emit Multisent(token, total);
        }
    }

    function multisendEther(
        address[] calldata targets,
        uint256[] calldata amounts
    ) public payable override {
        require(targets.length == amounts.length, "Length mismatched");

        uint256 total;
        for (uint256 i = 0; i < targets.length; i++) {
            total += amounts[i];
            payable(targets[i]).transfer(amounts[i]);
        }

        // In case someone tries to claim the ether inside the contract
        // by sending a higher sum of total amount than msg.value
        require(total == msg.value, "Total mismatched");

        emit Multisent(address(0), total);
    }



    function _safeTransferFromEnsureExactAmount(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) private {
        uint256 balanceBefore = token.balanceOf(to);
        token.safeTransferFrom(from, to, amount);
        require(
            token.balanceOf(to) - balanceBefore == (from != to ? amount : 0), // if from is the same as to, the final balance should be the same as before the transfer
            "Not enough tokens were transfered, check tax and fee options or try setting ensureExactAmount to false"
        );
    }

    function _safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 amount
    ) private {
        token.safeTransferFrom(from, to, amount);
    }

    function setPlatformFee(uint256 _platformFee) external onlyOwner {
        require(_platformFee > 0, "Platform fee must be greater than zero");
        platformFee = _platformFee;
    }

    function getPlatformFee() external view returns (uint256) {
        return platformFee;
    }

    function setFeeWalletAddress(address _feeWalletAddress) external onlyOwner {
        require(_feeWalletAddress != address(0), "Invalid fee wallet address");
        feeWalletAddress = _feeWalletAddress;
    }

    function getFeeWalletAddress() external view returns (address) {
        return feeWalletAddress;
    }

 function withdrawWronglySentEther(address to) external onlyOwner {
    require(to != address(0), "Invalid address");
    (bool success, ) = to.call{value: address(this).balance}("");
    require(success, "Ether transfer failed");
}


    function withdrawWronglySentToken(address token, address to) external onlyOwner {
        require(token != address(0), "Invalid token address");
        require(to != address(0), "Invalid recipient address");
        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
    }
}