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

import {GovToken} from "./governance/GovToken.sol";
import {Vault} from "./Vault.sol";

contract NexTrack is Ownable {
    /*//////////////////////////////////////////////////////////
                        ERRORS
    //////////////////////////////////////////////////////////*/

    error NexTrack__NotRegisteredManufacturer();
    error NexTrack__NotCurrentOwner();
    error NexTrack__NotIntendedRecipient();
    error NexTrack__QuantityExceedsAvailable();
    error NexTrack__RequestStillPending();
    error NexTrack__RequestAlreadyRejected();
    error NexTrack__RequestAlreadyApproved();
    error NexTrack__RequestAlreadyCompleted();
    error NexTrack__QuantityCannotBeZero();

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

    enum RequestStatus {
        Pending,
        Approved,
        Rejected,
        Completed
    }

    // STRUCTS
    struct ProductBatch {
        uint256 batchId; // Unique product ID
        string name; // Product name
        string description; // Product description
        Category category; // Product category
        address owner; // Current supply chain owner
        uint256 totalQuantity; // Number of items in this batch
        uint256 unitPrice; // Unit price
        uint256 parentBatch; // Parent batch ID
        uint256 timestamp; // Last update timestamp
    }

    struct TransferRequest {
        uint256 requestId;
        uint256 batchId;
        address seller;
        address buyer;
        uint256 quantityRequested;
        uint256 totalAmount;
        RequestStatus status;
        uint256 timestamp;
    }

    /*//////////////////////////////////////////////////////////
                        STATE VARIABLES
    //////////////////////////////////////////////////////////*/

    mapping(uint256 => ProductBatch) private s_batches; // Maps batch IDs to their details
    mapping(address => uint256[]) private s_currentInventory; // Tracks current inventory, maps address to a list of batch IDs
    mapping(address => bool) private s_registeredManufacturers; // Maps manufacturers to a boolean value indicating if they are registered

    mapping(uint256 => TransferRequest) private s_transferRequests;
    mapping(address => uint256[]) private s_sellerTransferRequests; // Maps sellers to a list of transfer request IDs raised by buyers
    mapping(address => uint256[]) private s_buyerTransferRequests; // Maps buyers to a list of transfer request IDs raised by them

    address[] private s_manufacturers;
    GovToken private immutable s_govToken;
    Vault private immutable s_vault;

    uint256 public constant DEFAULT_BATCH_ID = 0;
    uint256 public constant DEFAULT_QUANTITY_TO_SHIP = 0;

    /*//////////////////////////////////////////////////////////
                        EVENTS
    //////////////////////////////////////////////////////////*/

    event NewManufacturerOnboarded(address manufacturer);

    event ProductBatchRegistered(
        uint256 indexed batchId,
        string name,
        string description,
        Category category,
        address indexed owner,
        uint256 totalQuantity,
        uint256 unitPrice,
        uint256 indexed parentBatch,
        uint256 timestamp
    );

    event RequestCompleted(uint256 indexed requestId, address indexed buyer, uint256 timestamp);

    event ReceivedAndCreatedBatch(
        uint256 indexed requestId,
        uint256 indexed batchId,
        string name,
        string description,
        Category category,
        address indexed owner,
        uint256 totalQuantity,
        uint256 unitPrice,
        uint256 parentBatch,
        uint256 timestamp
    );

    event ProductBatchRequested(
        uint256 indexed requestId,
        uint256 indexed batchId,
        address indexed seller,
        address buyer,
        uint256 quantityRequested,
        uint256 totalAmount,
        RequestStatus status,
        uint256 timestamp
    );

    event TransferApproved(
        uint256 indexed requestId, uint256 indexed batchId, address indexed buyer, uint256 quantity, uint256 timestamp
    );

    event TransferRejected(
        uint256 indexed requestId, uint256 indexed batchId, address indexed buyer, uint256 quantity, uint256 timestamp
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
        if (s_transferRequests[requestId].buyer != msg.sender) {
            revert NexTrack__NotIntendedRecipient();
        }
        _;
    }

    modifier validateRequestStatus(uint256 requestId) {
        if (s_transferRequests[requestId].status == RequestStatus.Approved) {
            revert NexTrack__RequestAlreadyApproved();
        }
        if (s_transferRequests[requestId].status == RequestStatus.Rejected) {
            revert NexTrack__RequestAlreadyRejected();
        }
        if (s_transferRequests[requestId].status == RequestStatus.Completed) {
            revert NexTrack__RequestAlreadyCompleted();
        }
        _;
    }

    modifier validateStatusBeforeConfirm(uint256 requestId) {
        if (s_transferRequests[requestId].status == RequestStatus.Pending) {
            revert NexTrack__RequestStillPending();
        }
        if (s_transferRequests[requestId].status == RequestStatus.Rejected) {
            revert NexTrack__RequestAlreadyRejected();
        }
        if (s_transferRequests[requestId].status == RequestStatus.Completed) {
            revert NexTrack__RequestAlreadyCompleted();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////
                        FUNCTIONS
    //////////////////////////////////////////////////////////*/

    constructor(address[] memory manufacturers, GovToken govToken, Vault vault) Ownable(msg.sender) {
        s_govToken = govToken;
        s_vault = vault;

        for (uint256 i = 0; i < manufacturers.length; i++) {
            s_registeredManufacturers[manufacturers[i]] = true;
            s_manufacturers.push(manufacturers[i]);
        }
    }

    function onboardNewManufacturer(address manufacturer) public onlyOwner {
        s_registeredManufacturers[manufacturer] = true;
        s_manufacturers.push(manufacturer);
        s_govToken.mint(manufacturer, 1);
        emit NewManufacturerOnboarded(manufacturer);
    }

    function registerProductBatch(
        string memory name,
        string memory description,
        Category category,
        uint256 totalQuantity,
        uint256 unitPrice
    ) public onlyRegisteredManufacturer {
        _registerProductBatch(name, description, category, totalQuantity, unitPrice);
    }

    function requestProductBatch(uint256 batchId, address seller, uint256 quantityRequested)
        public
        returns (uint256 requestId)
    {
        if (quantityRequested == 0) {
            revert NexTrack__QuantityCannotBeZero();
        }

        ProductBatch memory batch = s_batches[batchId];
        if (batch.totalQuantity < quantityRequested) {
            revert NexTrack__QuantityExceedsAvailable();
        }
        return _requestProductBatch(batchId, seller, quantityRequested);
    }

    // initiate -> already approved/rejected/completed
    // reject -> already approved/rejected/completed
    // confirm -> still pending/ already rejected/completed

    function approveTransfer(uint256 requestId) public onlyBatchOwner(requestId) validateRequestStatus(requestId) {
        _approveTransfer(requestId);
    }

    function rejectTransfer(uint256 requestId) public onlyBatchOwner(requestId) validateRequestStatus(requestId) {
        _rejectTransfer(requestId);
    }

    function confirmTransfer(uint256 requestId)
        public
        validateStatusBeforeConfirm(requestId)
        onlyIntendedRecipient(requestId)
        returns (uint256, uint256)
    {
        return (requestId, _confirmTransfer(requestId));
    }

    /*////////////////////////////////////////////////////
                    INTERNAL FUNCTIONS
    ////////////////////////////////////////////////////*/

    function _registerProductBatch(
        string memory name,
        string memory description,
        Category category,
        uint256 totalQuantity,
        uint256 unitPrice
    ) internal {
        uint256 batchId = _generateProductId(name, category, totalQuantity, DEFAULT_BATCH_ID);

        ProductBatch memory newProductBatch = ProductBatch({
            batchId: batchId,
            name: name,
            description: description,
            category: category,
            owner: msg.sender,
            totalQuantity: totalQuantity,
            unitPrice: unitPrice,
            parentBatch: DEFAULT_BATCH_ID,
            timestamp: block.timestamp
        });

        s_batches[batchId] = newProductBatch;
        s_currentInventory[msg.sender].push(batchId);

        emit ProductBatchRegistered(
            batchId,
            name,
            description,
            category,
            msg.sender,
            totalQuantity,
            unitPrice,
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
        uint64 batchId = uint64(
            bytes8(
                keccak256(abi.encodePacked(name, category, totalQuantity, parentBatchId, msg.sender, block.timestamp))
            )
        );
        return batchId;
    }

    function _generateRequestId(uint256 batchId, address seller, uint256 quantityRequested)
        internal
        view
        returns (uint256)
    {
        return uint64(bytes8(keccak256(abi.encodePacked(batchId, seller, quantityRequested, block.timestamp))));
    }

    function _requestProductBatch(uint256 batchId, address seller, uint256 quantityRequested)
        internal
        returns (uint256 requestId)
    {
        requestId = _generateRequestId(batchId, seller, quantityRequested);
        uint256 totalAmount = quantityRequested * s_batches[batchId].unitPrice;

        TransferRequest memory transferRequest = TransferRequest({
            requestId: requestId,
            batchId: batchId,
            seller: seller,
            buyer: msg.sender,
            quantityRequested: quantityRequested,
            totalAmount: totalAmount,
            status: RequestStatus.Pending,
            timestamp: block.timestamp
        });

        s_transferRequests[transferRequest.requestId] = transferRequest;
        s_sellerTransferRequests[seller].push(transferRequest.requestId);
        s_buyerTransferRequests[msg.sender].push(transferRequest.requestId);

        s_vault.deposit(requestId, msg.sender, totalAmount);

        emit ProductBatchRequested(
            transferRequest.requestId,
            batchId,
            seller,
            msg.sender,
            quantityRequested,
            totalAmount,
            RequestStatus.Pending,
            block.timestamp
        );

        return transferRequest.requestId;
    }

    function _approveTransfer(uint256 requestId) internal {
        TransferRequest storage request = s_transferRequests[requestId];
        ProductBatch storage batch = s_batches[request.batchId];
        request.status = RequestStatus.Approved;
        request.timestamp = block.timestamp;
        batch.timestamp = block.timestamp;

        emit TransferApproved(requestId, request.batchId, request.buyer, request.quantityRequested, block.timestamp);
    }

    function _rejectTransfer(uint256 requestId) internal {
        TransferRequest storage request = s_transferRequests[requestId];
        request.status = RequestStatus.Rejected;
        request.timestamp = block.timestamp;

        s_vault.refund(requestId, request.buyer);
        emit TransferRejected(requestId, request.batchId, request.buyer, request.quantityRequested, block.timestamp);
    }

    function _confirmTransfer(uint256 requestId) internal returns (uint256) {
        TransferRequest storage request = s_transferRequests[requestId];
        uint256 batchId = request.batchId;
        ProductBatch storage oldBatch = s_batches[batchId];
        uint256 quantityReceived = request.quantityRequested;

        // Update parent batch
        oldBatch.timestamp = block.timestamp;
        oldBatch.totalQuantity -= quantityReceived;

        request.status = RequestStatus.Completed;
        request.timestamp = block.timestamp;

        uint256 newBatchId = _generateProductId(oldBatch.name, oldBatch.category, quantityReceived, batchId);

        // Create new batch
        // Directly store new batch
        s_batches[newBatchId] = ProductBatch({
            batchId: newBatchId,
            name: oldBatch.name,
            description: oldBatch.description,
            category: oldBatch.category,
            owner: msg.sender,
            totalQuantity: quantityReceived,
            unitPrice: oldBatch.unitPrice,
            parentBatch: batchId,
            timestamp: block.timestamp
        });
        s_currentInventory[msg.sender].push(newBatchId);

        // Transfer money to seller
        s_vault.withdraw(requestId, oldBatch.owner);

        // Emit events
        emit RequestCompleted(requestId, msg.sender, block.timestamp);
        emit ReceivedAndCreatedBatch(
            requestId,
            newBatchId,
            oldBatch.name,
            oldBatch.description,
            oldBatch.category,
            msg.sender,
            quantityReceived,
            oldBatch.unitPrice,
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

    function getBatchDetails(uint256 batchId) public view returns (ProductBatch memory) {
        return s_batches[batchId];
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

    function getRegisteredManufacturers() public view returns (address[] memory) {
        return s_manufacturers;
    }

    function getGovernanceTokenAddress() public view returns (address) {
        return address(s_govToken);
    }

    function getVaultAddress() public view returns (address) {
        return address(s_vault);
    }
}
