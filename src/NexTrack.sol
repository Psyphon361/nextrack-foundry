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
import {TimeLock} from "./governance/TimeLock.sol";
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
        bool isListed; // Is the batch listed on the marketplace
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

    mapping(uint256 => TransferRequest) private s_transferRequests; // Maps transfer request IDs to their details
    mapping(address => uint256[]) private s_sellerTransferRequests; // Maps sellers to a list of transfer request IDs raised by buyers
    mapping(address => uint256[]) private s_buyerTransferRequests; // Maps buyers to a list of transfer request IDs raised by them

    address[] private s_manufacturers;
    uint256[] private s_batchIds;
    GovToken private immutable s_govToken;
    TimeLock private immutable s_timelock;
    Vault private immutable s_vault;

    uint256 private constant DEFAULT_BATCH_ID = 0;
    uint256 private constant PRECISION = 1e18;

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

    event ProductBatchListed(uint256 indexed batchId, address indexed owner, string name, Category category, uint256 totalQuantity, uint256 unitPrice, uint256 timestamp);
    event ProductBatchDelisted(uint256 indexed batchId, address indexed owner, string name, Category category, uint256 totalQuantity, uint256 unitPrice, uint256 timestamp);
    event ProductBatchUnitPriceUpdated(uint256 indexed batchId, address indexed owner, uint256 oldUnitPrice, uint256 newUnitPrice, uint256 timestamp);

    /*//////////////////////////////////////////////////////////
                        MODIFIERS
    //////////////////////////////////////////////////////////*/

    modifier onlyRegisteredManufacturer() {
        if (!s_registeredManufacturers[msg.sender]) {
            revert NexTrack__NotRegisteredManufacturer();
        }
        _;
    }

    modifier callerIsBatchOwner(uint256 requestId) {
        uint256 batchId = s_transferRequests[requestId].batchId;

        if (s_batches[batchId].owner != msg.sender) {
            revert NexTrack__NotCurrentOwner();
        }
        _;
    }

    modifier onlyProductBatchOwner(uint256 batchId) {
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

    /// @notice Initializes the NexTrack contract with initial manufacturers and required contract addresses
    /// @dev Sets up the governance token, timelock, vault, and registers initial manufacturers
    /// @param manufacturers Array of initial manufacturer addresses to register
    /// @param govToken Address of the governance token contract
    /// @param vault Address of the vault contract
    /// @param timelock Address of the timelock contract
    constructor(address[] memory manufacturers, GovToken govToken, Vault vault, TimeLock timelock) Ownable(msg.sender) {
        s_govToken = govToken;
        s_timelock = timelock;
        s_vault = vault;
        s_manufacturers = manufacturers;
        for (uint256 i = 0; i < s_manufacturers.length; i++) {
            s_registeredManufacturers[manufacturers[i]] = true;
        }
    }

    /// @notice Onboards a new manufacturer to the NexTrack system
    /// @dev Only the contract owner can call this function (timelock contract)
    /// @param manufacturer The address of the manufacturer to onboard
    /// @custom:emits NewManufacturerOnboarded event
    function onboardNewManufacturer(address manufacturer) public onlyOwner {
        s_registeredManufacturers[manufacturer] = true;
        s_manufacturers.push(manufacturer);
        s_govToken.mint(manufacturer, 1 * PRECISION);
        emit NewManufacturerOnboarded(manufacturer);
    }

    /// @notice Registers a new product batch in the system
    /// @dev Only registered manufacturers can call this function
    /// @param name Name of the product batch
    /// @param description Description of the product batch
    /// @param category Category of the product
    /// @param totalQuantity Total quantity of items in the batch
    /// @param unitPrice Price per unit in the batch
    /// @custom:emits ProductBatchRegistered event
    function registerProductBatch(
        string memory name,
        string memory description,
        Category category,
        uint256 totalQuantity,
        uint256 unitPrice
    ) public onlyRegisteredManufacturer {
        _registerProductBatch(name, description, category, totalQuantity, unitPrice);
    }

    /// @notice Request to purchase a specific quantity from a product batch
    /// @dev Requires the requested quantity to be available in the batch
    /// @param batchId ID of the batch to purchase from
    /// @param quantityRequested Amount of items requested to purchase
    /// @return requestId The ID of the created transfer request
    /// @custom:emits ProductBatchRequested event
    function requestProductBatch(uint256 batchId, uint256 quantityRequested)
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
        return _requestProductBatch(batchId, quantityRequested);
    }

    /// @notice Approves a pending transfer request
    /// @dev Only the current batch owner can approve the transfer
    /// @param requestId ID of the transfer request to approve
    /// @custom:emits TransferApproved event
    function approveTransfer(uint256 requestId) public callerIsBatchOwner(requestId) validateRequestStatus(requestId) {
        _approveTransfer(requestId);
    }

    /// @notice Rejects a pending transfer request
    /// @dev Only the current batch owner can reject the transfer
    /// @param requestId ID of the transfer request to reject
    /// @custom:emits TransferRejected event
    function rejectTransfer(uint256 requestId) public callerIsBatchOwner(requestId) validateRequestStatus(requestId) {
        _rejectTransfer(requestId);
    }

    /// @notice Confirms a transfer after it has been approved
    /// @dev Only the intended recipient (buyer) can confirm the transfer
    /// @param requestId ID of the transfer request to confirm
    /// @return A tuple containing the request ID and the new batch ID
    /// @custom:emits RequestCompleted and ReceivedAndCreatedBatch events
    function confirmTransfer(uint256 requestId)
        public
        validateStatusBeforeConfirm(requestId)
        onlyIntendedRecipient(requestId)
        returns (uint256, uint256)
    {
        return (requestId, _confirmTransfer(requestId));
    }

    /// @notice Lists a product batch on the marketplace
    /// @dev Only the batch owner can list their batch
    /// @param batchId ID of the batch to list
    /// @custom:emits ProductBatchListed event
    function listProductBatch(uint256 batchId) public onlyProductBatchOwner(batchId) {
        ProductBatch storage batch = s_batches[batchId];
        batch.isListed = true;
        emit ProductBatchListed(batchId, batch.owner, batch.name, batch.category, batch.totalQuantity, batch.unitPrice, batch.timestamp);
    }

    /// @notice Removes a product batch from the marketplace listing
    /// @dev Only the batch owner can delist their batch
    /// @param batchId ID of the batch to delist
    /// @custom:emits ProductBatchDelisted event
    function delistProductBatch(uint256 batchId) public onlyProductBatchOwner(batchId) {
        ProductBatch storage batch = s_batches[batchId];
        batch.isListed = false;
        emit ProductBatchDelisted(batchId, batch.owner, batch.name, batch.category, batch.totalQuantity, batch.unitPrice, batch.timestamp);
    }

    /// @notice Updates the unit price of a product batch
    /// @dev Only the batch owner can update the price
    /// @param batchId ID of the batch to update
    /// @param newUnitPrice New price per unit
    /// @custom:emits ProductBatchUnitPriceUpdated event
    function updateBatchUnitPrice(uint256 batchId, uint256 newUnitPrice) public onlyProductBatchOwner(batchId) {
        ProductBatch storage batch = s_batches[batchId];
        uint256 oldUnitPrice = batch.unitPrice;
        batch.unitPrice = newUnitPrice * PRECISION;
        emit ProductBatchUnitPriceUpdated(batchId, batch.owner, oldUnitPrice, newUnitPrice, batch.timestamp);
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
            unitPrice: unitPrice * PRECISION,
            isListed: true,
            parentBatch: DEFAULT_BATCH_ID,
            timestamp: block.timestamp
        });

        s_batches[batchId] = newProductBatch;
        s_currentInventory[msg.sender].push(batchId);
        s_batchIds.push(batchId);

        emit ProductBatchRegistered(
            batchId,
            name,
            description,
            category,
            msg.sender,
            totalQuantity,
            unitPrice * PRECISION,
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

    function _requestProductBatch(uint256 batchId, uint256 quantityRequested)
        internal
        returns (uint256 requestId)
    {
        address seller = getBatchDetails(batchId).owner;
        requestId = _generateRequestId(batchId, seller, quantityRequested);
        uint256 totalAmount = quantityRequested * s_batches[batchId].unitPrice; // already in 18 decimal precision because of unitPrice

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
            isListed: false,
            parentBatch: batchId,
            timestamp: block.timestamp
        });
        s_currentInventory[msg.sender].push(newBatchId);
        s_batchIds.push(newBatchId);

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

    function getAllBatchIds() public view returns (uint256[] memory) {
        return s_batchIds;
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
