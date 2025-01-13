// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract NexTrack is Ownable {
    /*//////////////////////////////////////////////////////////
                        ERRORS
    //////////////////////////////////////////////////////////*/

    error NexTrack__NotRegisteredManufacturer();

    /*//////////////////////////////////////////////////////////
                        TYPE DECLARATIONS
    //////////////////////////////////////////////////////////*/

    // ENUMS
    enum Category {
        Electronics,
        Clothes,
        Luxury,
        Food,
        Medicine,
        Furniture,
        Books,
        Automobiles,
        Cosmetics,
        Other
    }

    enum Status {
        Manufactured,
        InTransit,
        InWarehouse,
        Delivered
    }

    // STRUCTS
    struct Product {
        uint256 id; // Unique product ID
        string name; // Product name
        string description; // Product description
        Category category; // Product category
        address currentOwner; // Current supply chain owner
        Status status; // Current status in supply chain
        address intendedReceiver; // Address of the specified recipient for the current transfer, set to address(0) if no transfer is in progress
        uint256 timestamp; // Last status update timestamp
    }

    /*//////////////////////////////////////////////////////////
                        STATE VARIABLES
    //////////////////////////////////////////////////////////*/

    mapping(uint256 => Product) public products; // Maps product IDs to their details
    mapping(uint256 => address[]) public productOwnershipHistory; // Tracks the ownership history of a product
    mapping(address => bool) public registeredManufacturers; // Maps manufacturers to a boolean value indicating if they are registered

    /*//////////////////////////////////////////////////////////
                        MODIFIERS
    //////////////////////////////////////////////////////////*/

    modifier onlyRegisteredManufacturer() {
        if (!registeredManufacturers[msg.sender]) {
            revert NexTrack__NotRegisteredManufacturer();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////
                        FUNCTIONS
    //////////////////////////////////////////////////////////*/

    constructor(address[] memory manufacturers) Ownable(msg.sender) {
        for (uint256 i = 0; i < manufacturers.length; i++) {
            registeredManufacturers[manufacturers[i]] = true;
        }
    }
}
