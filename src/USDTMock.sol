// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract USDTMock is ERC20, Ownable(msg.sender) {
    constructor() ERC20("USDT", "mUSDT") {}

    /// @notice Mints a certain amount of USDT tokens to a specific address
    /// @param to Address to mint the tokens to
    /// @param amount Amount of tokens to mint
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}