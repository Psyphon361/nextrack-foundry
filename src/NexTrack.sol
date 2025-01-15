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
    error NexTrack__TransferInitiationPending();
    error NexTrack__RequestAlreadyRejected();
    error NexTrack__RequestAlreadyApproved();
    error NexTrack__RequestAlreadyCompleted();

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

    enum ProductStatus {
        Manufactured,
        InTransit,
        InWarehouse,
        Delivered
    }

    enum RequestStatus {
        Pending,
        Approved,
        Rejected,
        Completed
    }

    // STRUCTS
    struct ProductBatch {
        uint256 id; // Unique product ID
        string name; // Product name
        string description; // Product description
        Category category; // Product category
        address owner; // Current supply chain owner
        ProductStatus status; // Current status in supply chain
        address intendedRecipient; // Address of the specified recipient for the current transfer, set to address(0) if no transfer is in progress
        uint256 totalQuantity; // Number of items in this batch
        uint256 quantityToShip;
        uint256 parentBatch; // Parent batch ID
        uint256 timestamp; // Last status update timestamp
    }

    struct TransferRequest {
        uint256 requestId;
        uint256 batchId;
        address seller;
        address buyer;
        uint256 quantityRequested;
        RequestStatus status;
        uint256 timestamp;
    }

    /*//////////////////////////////////////////////////////////
                        STATE VARIABLES
    //////////////////////////////////////////////////////////*/

    mapping(uint256 => ProductBatch) public s_batches; // Maps batch IDs to their details
    mapping(address => uint256[]) public s_currentInventory; // Tracks current inventory, maps address to a list of batch IDs
    mapping(address => bool) public s_registeredManufacturers; // Maps manufacturers to a boolean value indicating if they are registered

    mapping(uint256 => TransferRequest) public s_transferRequests;
    mapping(address => uint256[]) public s_sellerTransferRequests; // Maps sellers to a list of transfer request IDs raised by buyers
    mapping(address => uint256[]) public s_buyerTransferRequests; // Maps buyers to a list of transfer request IDs raised by them

    address[] public s_manufacturers;

    uint256 public constant DEFAULT_BATCH_ID = 0;
    uint256 public constant DEFAULT_QUANTITY_TO_SHIP = 0;

    /*//////////////////////////////////////////////////////////
                        EVENTS
    //////////////////////////////////////////////////////////*/

    event ProductBatchRegistered(
        uint256 indexed batchId,
        string indexed name,
        string description,
        Category category,
        address owner,
        ProductStatus status,
        address intendedRecipient,
        uint256 indexed totalQuantity,
        uint256 quantityToShip,
        uint256 parentBatch,
        uint256 timestamp
    );

    event RequestCompleted(
        uint256 indexed requestId,
        address indexed buyer,
        uint256 timestamp
    );

    event ReceivedAndCreatedBatch(
        uint256 indexed requestId,
        uint256 indexed batchId,
        string name,
        string description,
        Category category,
        address indexed owner,
        ProductStatus status,
        address intendedRecipient,
        uint256 totalQuantity,
        uint256 quantityToShip,
        uint256 parentBatch,
        uint256 timestamp
    );

    event TransferRequested(
        uint256 indexed requestId,
        uint256 indexed batchId,
        address indexed seller,
        address buyer,
        uint256 quantityRequested,
        RequestStatus status,
        uint256 timestamp
    );

    event TransferInitiated(
        uint256 indexed requestId, uint256 indexed batchId, address indexed intendedRecipient, uint256 quantity, uint256 timestamp
    );

    /*//////////////////////////////////////////////////////////
                        MODIFIERS
    //////////////////////////////////////////////////////////*/

    modifier onlyRegisteredManufacturer() {
        if (!s_registeredManufacturers[msg.sender]) {
            revert NexTrack__NotRegisteredManufacturer();
        }
        _;
    }

    modifier onlyBatchOwner(uint256 requestId) {
        uint256 batchId = s_transferRequests[requestId].batchId;


        if (s_batches[batchId].owner != msg.sender) {
            revert NexTrack__NotCurrentOwner();
        }
        _;
    }

    modifier onlyIntendedRecipient(uint256 requestId) {
        if (s_batches[s_transferRequests[requestId].batchId].intendedRecipient != msg.sender) {
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

    function registerProductBatch(
        string memory name,
        string memory description,
        Category category,
        uint256 totalQuantity
    ) public onlyRegisteredManufacturer {
        _registerProductBatch(name, description, category, totalQuantity);
    }

    function requestProductBatch(uint256 batchId, address seller, uint256 quantityRequested)
        public
        returns (uint256 requestId)
    {
        ProductBatch memory batch = s_batches[batchId];
        if (batch.totalQuantity < quantityRequested) {
            revert NexTrack__QuantityExceedsAvailable();
        }
        return _requestProductBatch(batchId, seller, quantityRequested);
    }

    function initiateTransfer(
        uint256 requestId
    ) public onlyBatchOwner(requestId) {
        if (s_transferRequests[requestId].status == RequestStatus.Approved) {
            revert NexTrack__RequestAlreadyApproved();
        }
        if(s_transferRequests[requestId].status == RequestStatus.Rejected) {
            revert NexTrack__RequestAlreadyRejected();
        }
        if(s_transferRequests[requestId].status == RequestStatus.Completed) {
            revert NexTrack__RequestAlreadyCompleted();
        }

        TransferRequest storage request = s_transferRequests[requestId];
        uint256 batchId = request.batchId;
        address intendedRecipient = request.buyer;
        uint256 quantityToShip = request.quantityRequested;

        _initiateTransfer(requestId, batchId, intendedRecipient, quantityToShip);
    }

    function rejectTransfer(uint256 requestId) public onlyBatchOwner(requestId) {}

    function confirmTransfer(uint256 requestId) public onlyIntendedRecipient(requestId) returns (uint256, uint256) {
        if (s_transferRequests[requestId].status == RequestStatus.Pending) {
            revert NexTrack__TransferInitiationPending();
        }
        if(s_transferRequests[requestId].status == RequestStatus.Rejected) {
            revert NexTrack__RequestAlreadyRejected();
        }
        if(s_transferRequests[requestId].status == RequestStatus.Completed) {
            revert NexTrack__RequestAlreadyCompleted();
        }

        uint256 batchId = s_transferRequests[requestId].batchId;
        return (requestId, _confirmTransfer(requestId, batchId));
    }

    /*//////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////*/

    function _registerProductBatch(
        string memory name,
        string memory description,
        Category category,
        uint256 totalQuantity
    ) internal {
        uint256 id = _generateProductId(name, category, totalQuantity, DEFAULT_BATCH_ID);

        ProductBatch memory newProductBatch = ProductBatch({
            id: id,
            name: name,
            description: description,
            category: category,
            owner: msg.sender,
            status: ProductStatus.Manufactured,
            intendedRecipient: address(0),
            totalQuantity: totalQuantity,
            quantityToShip: DEFAULT_QUANTITY_TO_SHIP,
            parentBatch: DEFAULT_BATCH_ID,
            timestamp: block.timestamp
        });

        s_batches[id] = newProductBatch;
        s_currentInventory[msg.sender].push(id);

        emit ProductBatchRegistered(
            id,
            name,
            description,
            category,
            msg.sender,
            ProductStatus.Manufactured,
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

    function _requestProductBatch(uint256 batchId, address seller, uint256 quantityRequested)
        internal
        returns (uint256 requestId)
    {
        TransferRequest memory transferRequest = TransferRequest({
            requestId: uint64(bytes8(keccak256(abi.encodePacked(batchId, seller, quantityRequested, block.timestamp)))),
            batchId: batchId,
            seller: seller,
            buyer: msg.sender,
            quantityRequested: quantityRequested,
            status: RequestStatus.Pending,
            timestamp: block.timestamp
        });

        s_transferRequests[transferRequest.requestId] = transferRequest;
        s_sellerTransferRequests[seller].push(transferRequest.requestId);
        s_buyerTransferRequests[msg.sender].push(transferRequest.requestId);

        emit TransferRequested(
            transferRequest.requestId,
            batchId,
            seller,
            msg.sender,
            quantityRequested,
            RequestStatus.Pending,
            block.timestamp
        );

        return transferRequest.requestId;
    }

    function _initiateTransfer(uint256 requestId, uint256 batchId, address intendedRecipient, uint256 quantityToShip) internal {
        ProductBatch storage batch = s_batches[batchId];
        s_transferRequests[requestId].status = RequestStatus.Approved;
        s_transferRequests[requestId].timestamp = block.timestamp;

        batch.status = ProductStatus.InTransit;
        batch.intendedRecipient = intendedRecipient;
        batch.timestamp = block.timestamp;
        batch.quantityToShip = quantityToShip;

        emit TransferInitiated(requestId, batchId, intendedRecipient, quantityToShip, block.timestamp);
    }

    function _confirmTransfer(uint256 requestId, uint256 batchId) internal returns (uint256) {
        ProductBatch storage oldBatch = s_batches[batchId];
        uint256 quantityReceived = oldBatch.quantityToShip;

        // Update parent batch
        oldBatch.status = ProductStatus.Manufactured;
        oldBatch.intendedRecipient = address(0);
        oldBatch.timestamp = block.timestamp;
        oldBatch.totalQuantity -= quantityReceived;
        oldBatch.quantityToShip = 0;

        s_transferRequests[requestId].status = RequestStatus.Completed;
        s_transferRequests[requestId].timestamp = block.timestamp;

        uint256 newBatchId = _generateProductId(oldBatch.name, oldBatch.category, quantityReceived, batchId);

        // Create new batch
        // Directly store new batch
        s_batches[newBatchId] = ProductBatch({
            id: newBatchId,
            name: oldBatch.name,
            description: oldBatch.description,
            category: oldBatch.category,
            owner: msg.sender,
            status: ProductStatus.InWarehouse,
            intendedRecipient: address(0),
            totalQuantity: quantityReceived,
            quantityToShip: 0,
            parentBatch: batchId,
            timestamp: block.timestamp
        });

        s_currentInventory[msg.sender].push(newBatchId);

        // Emit events
        emit RequestCompleted(requestId, msg.sender, block.timestamp); 

        emit ReceivedAndCreatedBatch(
            requestId,
            newBatchId,
            oldBatch.name,
            oldBatch.description,
            oldBatch.category,
            msg.sender,
            ProductStatus.InWarehouse,
            address(0),
            quantityReceived,
            DEFAULT_QUANTITY_TO_SHIP,
            batchId,
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

    function getBatchDetails(uint256 id) public view returns (ProductBatch memory) {
        return s_batches[id];
    }

    function getTransferRequestDetails(uint256 requestId) public view returns (TransferRequest memory) {
        return s_transferRequests[requestId];
    }

    function getSellerTransferRequests(address seller) public view returns (uint256[] memory) {
        return s_sellerTransferRequests[seller];
    }

    function getBuyerTransferRequests(address buyer) public view returns (uint256[] memory) {
        return s_buyerTransferRequests[buyer];
    }

    function getManufacturerCount() public view returns (uint256) {
        return s_manufacturers.length;
    }
}
