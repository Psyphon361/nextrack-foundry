// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {USDTMock} from "./USDTMock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Vault is Ownable {
    error Vault__CannotDepositAgain();

    USDTMock private immutable usdt;
    mapping(uint256 requestId => uint256 totalAmount) private s_totalAmounts;

    event Deposited(uint256 indexed requestId, address indexed sender, uint256 totalAmount);
    event Withdrawn(uint256 indexed requestId, address indexed recipient, uint256 totalAmount);
    event Refunded(uint256 indexed requestId, address indexed recipient, uint256 totalAmount);

    /// @notice Initializes the Vault contract with USDT token address
    /// @dev Sets up the USDT token interface and ownership
    /// @param _usdt Address of the USDT token contract
    constructor(address _usdt) Ownable(msg.sender) {
        usdt = USDTMock(_usdt);
    }

    /// @notice Allows the contract to receive native tokens
    /// @dev Required for receiving ETH/ETN
    receive() external payable {}

    /// @notice Deposits USDT tokens into the vault for a specific request
    /// @dev Only the owner (NexTrack contract) can call this function
    /// @param requestId ID of the transfer request
    /// @param sender Address sending the USDT tokens
    /// @param totalAmount Amount of USDT tokens to deposit
    /// @custom:emits Deposited event
    function deposit(uint256 requestId, address sender, uint256 totalAmount) public payable onlyOwner {
        if (s_totalAmounts[requestId] != 0) {
            revert Vault__CannotDepositAgain();
        }
        s_totalAmounts[requestId] = totalAmount;
        usdt.transferFrom(sender, address(this), totalAmount);
        emit Deposited(requestId, sender, totalAmount);
    }

    /// @notice Withdraws USDT tokens from the vault to the recipient (the seller)
    /// @dev Only the owner (NexTrack contract) can call this function
    /// @param requestId ID of the transfer request
    /// @param recipient Address to receive the USDT tokens
    /// @custom:emits Withdrawn event
    function withdraw(uint256 requestId, address recipient) public onlyOwner {
        uint256 totalAmount = s_totalAmounts[requestId];
        s_totalAmounts[requestId] = 0;
        usdt.transfer(recipient, totalAmount);
        emit Withdrawn(requestId, recipient, totalAmount);
    }

    /// @notice Refunds USDT tokens from the vault back to the original sender (the buyer)
    /// @dev Only the owner (NexTrack contract) can call this function
    /// @param requestId ID of the transfer request
    /// @param recipient Address to receive the refund
    /// @custom:emits Refunded event
    function refund(uint256 requestId, address recipient) public onlyOwner {
        uint256 totalAmount = s_totalAmounts[requestId];
        s_totalAmounts[requestId] = 0;
        usdt.transfer(recipient, totalAmount);
        emit Refunded(requestId, recipient, totalAmount);
    }

    /// @notice Gets the address of the USDT token contract
    /// @return Address of the USDT token contract
    function getUsdtAddress() external view returns (address) {
        return address(usdt);
    }

    /// @notice Gets the amount of USDT tokens held in escrow for a specific request
    /// @param requestId ID of the transfer request
    /// @return Amount of USDT tokens held for the request
    function getEscrowedAmountForRequest(uint256 requestId) external view returns (uint256) {
        return s_totalAmounts[requestId];
    }

    /// @notice Gets the total USDT balance held by the vault
    /// @return Total amount of USDT tokens in the vault
    function getVaultUsdtBalance() external view returns (uint256) {
        return usdt.balanceOf(address(this));
    }
}