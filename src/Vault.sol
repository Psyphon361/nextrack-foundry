// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {USDTMock} from "./USDTMock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Vault is Ownable {
    error Vault__CannotDepositAgain();

    USDTMock private immutable usdt;
    mapping(uint256 requestId => uint256 totalAmount) public s_totalAmounts;

    event Deposited(uint256 indexed requestId, address indexed sender, uint256 totalAmount);
    event Withdrawn(uint256 indexed requestId, address indexed recipient, uint256 totalAmount);
    event Refunded(uint256 indexed requestId, address indexed recipient, uint256 totalAmount);

    constructor(address _usdt) Ownable(msg.sender) {
        usdt = USDTMock(_usdt);
    }

    receive() external payable {}

    function deposit(uint256 requestId, address sender, uint256 totalAmount) public payable onlyOwner {
        if (s_totalAmounts[requestId] != 0) {
            revert Vault__CannotDepositAgain();
        }
        s_totalAmounts[requestId] = totalAmount;
        usdt.transferFrom(sender, address(this), totalAmount);
        emit Deposited(requestId, sender, totalAmount);
    }

    function withdraw(uint256 requestId, address recipient) public onlyOwner {
        uint256 totalAmount = s_totalAmounts[requestId];
        s_totalAmounts[requestId] = 0;
        usdt.transfer(recipient, totalAmount);
        emit Withdrawn(requestId, recipient, totalAmount);
    }

    function refund(uint256 requestId, address recipient) public onlyOwner {
        uint256 totalAmount = s_totalAmounts[requestId];
        s_totalAmounts[requestId] = 0;
        usdt.transfer(recipient, totalAmount);
        emit Refunded(requestId, recipient, totalAmount);
    }

    function getUsdtAddress() external view returns (address) {
        return address(usdt);
    }
}
