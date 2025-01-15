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
    error NexTrack__NotCurrentOwner();
    error NexTrack__NotIntendedRecipient();
    error NexTrack__QuantityExceedsAvailable();

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
    struct ProductBatch {
        uint256 id; // Unique product ID
        string name; // Product name
        string description; // Product description
        Category category; // Product category
        address owner; // Current supply chain owner
        Status status; // Current status in supply chain
        address intendedRecipient; // Address of the specified recipient for the current transfer, set to address(0) if no transfer is in progress
        uint256 totalQuantity; // Number of items in this batch
        uint256 quantityToShip;
        uint256 parentBatch; // Parent batch ID
        uint256 timestamp; // Last status update timestamp
    }

    /*//////////////////////////////////////////////////////////
                        STATE VARIABLES
    //////////////////////////////////////////////////////////*/

    mapping(uint256 => ProductBatch) public s_batches; // Maps batch IDs to their details
    mapping(address => uint256[]) public s_currentInventory; // Tracks current inventory, maps address to a list of batch IDs
    mapping(address => bool) public s_registeredManufacturers; // Maps manufacturers to a boolean value indicating if they are registered
    address[] public s_manufacturers;

    uint256 public constant DEFAULT_BATCH_ID = 0;
    uint256 public constant DEFAULT_QUANTITY_TO_SHIP = 0;

    /*//////////////////////////////////////////////////////////
                        EVENTS
    //////////////////////////////////////////////////////////*/

    event ProductRegistered(
        uint256 indexed id,
        string indexed name,
        string description,
        Category category,
        address owner,
        Status status,
        address intendedRecipient,
        uint256 indexed totalQuantity,
        uint256 quantityToShip,
        uint256 parentBatch,
        uint256 timestamp
    );

    event ReceivedAndCreatedBatch(
        uint256 indexed id,
        string indexed name,
        string description,
        Category category,
        address owner,
        Status status,
        address intendedRecipient,
        uint256 indexed totalQuantity,
        uint256 quantityToShip,
        uint256 parentBatch,
        uint256 timestamp
    );

    event TransferInitiated(
        uint256 indexed id, address indexed intendedRecipient, uint256 indexed quantity, uint256 timestamp
    );

    event ProductReceived(uint256 indexed id, uint256 indexed totalQuantity, uint256 timestamp);

    /*//////////////////////////////////////////////////////////
                        MODIFIERS
    //////////////////////////////////////////////////////////*/

    modifier onlyRegisteredManufacturer() {
        if (!s_registeredManufacturers[msg.sender]) {
            revert NexTrack__NotRegisteredManufacturer();
        }
        _;
    }

    modifier onlyBatchOwner(uint256 id) {
        if (s_batches[id].owner != msg.sender) {
            revert NexTrack__NotCurrentOwner();
        }
        _;
    }

    modifier onlyIntendedRecipient(uint256 id) {
        if (s_batches[id].intendedRecipient != msg.sender) {
            revert NexTrack__NotIntendedRecipient();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////
                        FUNCTIONS
    //////////////////////////////////////////////////////////*/

    constructor(address[] memory manufacturers) Ownable(msg.sender) {
        for (uint256 i = 0; i < manufacturers.length; i++) {
            s_registeredManufacturers[manufacturers[i]] = true;
            s_manufacturers.push(manufacturers[i]);
        }
    }

    function registerProduct(string memory name, string memory description, Category category, uint256 totalQuantity)
        public
        onlyRegisteredManufacturer
    {
        _registerProduct(name, description, category, totalQuantity);
    }

    function initiateTransfer(uint256 id, address intendedRecipient, uint256 quantityToShip)
        public
        onlyBatchOwner(id)
    {
        if (quantityToShip > s_batches[id].totalQuantity) {
            revert NexTrack__QuantityExceedsAvailable();
        }
        _initiateTransfer(id, intendedRecipient, quantityToShip);
    }

    function confirmTransfer(uint256 id) public onlyIntendedRecipient(id) returns (uint256 newBatchId) {
        // 1. update the original batch -> reset intendedRecipient and status to Manufactured
        // 2. create a new batch with the received quantity and status to InWarehouse
        return _confirmTransfer(id);
    }

    /*//////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////*/

    function _registerProduct(string memory name, string memory description, Category category, uint256 totalQuantity)
        internal
    {
        uint256 id = _generateProductId(name, category, totalQuantity, DEFAULT_BATCH_ID);

        ProductBatch memory newProductBatch = ProductBatch({
            id: id,
            name: name,
            description: description,
            category: category,
            owner: msg.sender,
            status: Status.Manufactured,
            intendedRecipient: address(0),
            totalQuantity: totalQuantity,
            quantityToShip: DEFAULT_QUANTITY_TO_SHIP,
            parentBatch: DEFAULT_BATCH_ID,
            timestamp: block.timestamp
        });

        s_batches[id] = newProductBatch;
        s_currentInventory[msg.sender].push(id);

        emit ProductRegistered(
            id,
            name,
            description,
            category,
            msg.sender,
            Status.Manufactured,
            address(0),
            totalQuantity,
            DEFAULT_QUANTITY_TO_SHIP,
            DEFAULT_BATCH_ID,
            block.timestamp
        );
    }

    function _generateProductId(string memory name, Category category, uint256 totalQuantity, uint256 parentBatchId)
        internal
        view
        returns (uint256)
    {
        // Generate a unique product ID based on the product details and timestamp
        uint64 id = uint64(
            bytes8(
                keccak256(abi.encodePacked(name, category, totalQuantity, parentBatchId, msg.sender, block.timestamp))
            )
        );
        return id;
    }

    function _initiateTransfer(uint256 id, address intendedRecipient, uint256 quantityToShip) internal {
        ProductBatch storage batch = s_batches[id];

        batch.status = Status.InTransit;
        batch.intendedRecipient = intendedRecipient;
        batch.timestamp = block.timestamp;
        batch.quantityToShip = quantityToShip;

        emit TransferInitiated(id, intendedRecipient, quantityToShip, block.timestamp);
    }

    function _confirmTransfer(uint256 id) internal returns (uint256) {
        ProductBatch storage oldBatch = s_batches[id];
        uint256 quantityReceived = oldBatch.quantityToShip;

        // Update parent batch
        oldBatch.status = Status.Manufactured;
        oldBatch.intendedRecipient = address(0);
        oldBatch.timestamp = block.timestamp;
        oldBatch.totalQuantity -= quantityReceived;
        oldBatch.quantityToShip = 0;

        uint256 newBatchId = _generateProductId(oldBatch.name, oldBatch.category, quantityReceived, id);

        // Create new batch
        ProductBatch memory newProductBatch = ProductBatch({
            id: newBatchId,
            name: oldBatch.name,
            description: oldBatch.description,
            category: oldBatch.category,
            owner: msg.sender,
            status: Status.InWarehouse,
            intendedRecipient: address(0),
            totalQuantity: quantityReceived,
            quantityToShip: 0,
            parentBatch: id,
            timestamp: block.timestamp
        });

        s_batches[newBatchId] = newProductBatch;
        s_currentInventory[msg.sender].push(newBatchId);

        // Emit event
        emit ReceivedAndCreatedBatch(
            newBatchId,
            newProductBatch.name,
            newProductBatch.description,
            newProductBatch.category,
            newProductBatch.owner,
            Status.InWarehouse,
            address(0),
            quantityReceived,
            DEFAULT_QUANTITY_TO_SHIP,
            id,
            block.timestamp
        );

        return newBatchId;
    }

    /*//////////////////////////////////////////////////////////
                        GETTER FUNCTIONS
    //////////////////////////////////////////////////////////*/

    function getCurrentInventory(address owner) public view returns (uint256[] memory) {
        return s_currentInventory[owner];
    }

    function getProductDetails(uint256 id) public view returns (ProductBatch memory) {
        return s_batches[id];
    }

    function getManufacturerCount() public view returns (uint256) {
        return s_manufacturers.length;
    }
}
