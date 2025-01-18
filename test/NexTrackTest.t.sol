// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {DeployNexTrack} from "../script/DeployNexTrack.s.sol";
import {NexTrack} from "../src/NexTrack.sol";

contract NexTrackTest is Test {
    DeployNexTrack public deployer;
    NexTrack public nexTrack;

    address public USER = makeAddr("user");
    address public RANDOM_USER = makeAddr("random_user");
    address public REGISTERED_MANUFACTURER = address(1);

    string public name = "Earphones";
    string public description = "High quality earphones";
    NexTrack.Category public category = NexTrack.Category.Electronics;
    uint256 public TOTAL_QUANTITY = 100;
    uint256 public QUANTITY_TO_SHIP = 30;

    uint256 public constant DEFAULT_BATCH_ID = 0;
    uint256 public constant DEFAULT_QUANTITY_TO_SHIP = 0;

    ///////////////////////
    /// SetUp Function ////
    ///////////////////////

    function setUp() public {
        deployer = new DeployNexTrack();
        nexTrack = deployer.run();
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////

    function testContractDeployment() public view {
        console2.log("NexTrack Address: ", address(nexTrack));
        assert(address(nexTrack) != address(0));

        uint256 manufacturerCount = nexTrack.getManufacturerCount();
        console2.log("Manufacturer Count: ", manufacturerCount);

        assertEq(manufacturerCount, 10);
    }

    ////////////////////////////
    // Register Product Tests //
    ////////////////////////////

    function testRevertsIfNotRegisteredManufacturer() public {
        vm.expectRevert(NexTrack.NexTrack__NotRegisteredManufacturer.selector);
        vm.prank(USER);
        nexTrack.registerProductBatch(name, description, category, TOTAL_QUANTITY);
    }

    function testRegisterProduct() public {
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.registerProductBatch(name, description, category, TOTAL_QUANTITY);

        uint256 batchId = nexTrack.getCurrentInventory(REGISTERED_MANUFACTURER)[0];
        NexTrack.ProductBatch memory productBatch = nexTrack.getBatchDetails(batchId);

        assertEq(productBatch.name, name);
        assertEq(productBatch.description, description);
        assertEq(uint8(productBatch.category), uint8(category));
        assertEq(productBatch.owner, REGISTERED_MANUFACTURER);
    }

    function testEmitsEventOnProductRegistration() public {
        vm.expectEmit(true, true, true, true, address(nexTrack));
        emit NexTrack.ProductBatchRegistered(
            uint64(
                bytes8(
                    keccak256(
                        abi.encodePacked(
                            name, category, TOTAL_QUANTITY, DEFAULT_BATCH_ID, REGISTERED_MANUFACTURER, block.timestamp
                        )
                    )
                )
            ),
            name,
            description,
            category,
            REGISTERED_MANUFACTURER,
            TOTAL_QUANTITY,
            DEFAULT_BATCH_ID,
            block.timestamp
        );
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.registerProductBatch(name, description, category, TOTAL_QUANTITY);
    }

    ////////////////////////////
    // Request Product Tests ///
    ////////////////////////////

    modifier productRegistered() {
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.registerProductBatch(name, description, category, TOTAL_QUANTITY);
        _;
    }

    function testRevertsIfQuantityExceedsAvailable() public productRegistered {
        uint256 batchId = nexTrack.getCurrentInventory(REGISTERED_MANUFACTURER)[0];
        vm.expectRevert(NexTrack.NexTrack__QuantityExceedsAvailable.selector);
        nexTrack.requestProductBatch(batchId, USER, TOTAL_QUANTITY + 1);
    }

    function testRequestProductBatch() public productRegistered {
        uint256 batchId = nexTrack.getCurrentInventory(REGISTERED_MANUFACTURER)[0];
        vm.prank(USER);
        uint256 requestId = nexTrack.requestProductBatch(batchId, REGISTERED_MANUFACTURER, QUANTITY_TO_SHIP);

        NexTrack.TransferRequest memory requestDetails = nexTrack.getTransferRequestDetails(requestId);
        assertEq(requestDetails.batchId, batchId);
        assertEq(requestDetails.seller, REGISTERED_MANUFACTURER);
        assertEq(requestDetails.buyer, USER);
        assertEq(requestDetails.quantityRequested, QUANTITY_TO_SHIP);
        assertEq(uint8(requestDetails.status), uint8(NexTrack.RequestStatus.Pending));

        uint256 sellerRequestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        uint256 buyerRequestId = nexTrack.getBuyerTransferRequests(USER)[0];
        assertEq(sellerRequestId, buyerRequestId);
    }

    function testEmitsEventOnProductRequest() public productRegistered {
        uint256 batchId = nexTrack.getCurrentInventory(REGISTERED_MANUFACTURER)[0];
        vm.expectEmit(true, true, true, true, address(nexTrack));
        emit NexTrack.TransferRequested(
            uint64(
                bytes8(keccak256(abi.encodePacked(batchId, REGISTERED_MANUFACTURER, QUANTITY_TO_SHIP, block.timestamp)))
            ),
            batchId,
            REGISTERED_MANUFACTURER,
            USER,
            QUANTITY_TO_SHIP,
            NexTrack.RequestStatus.Pending,
            block.timestamp
        );
        vm.prank(USER);
        nexTrack.requestProductBatch(batchId, REGISTERED_MANUFACTURER, QUANTITY_TO_SHIP);
    }

    ////////////////////////////////
    //// Approve Transfer Tests ////
    ////////////////////////////////

    modifier productRequested() {
        uint256 batchId = nexTrack.getCurrentInventory(REGISTERED_MANUFACTURER)[0];
        vm.prank(USER);
        nexTrack.requestProductBatch(batchId, REGISTERED_MANUFACTURER, QUANTITY_TO_SHIP);
        _;
    }

    modifier transferApproved() {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.approveTransfer(requestId);
        _;
    }

    modifier transferRejected() {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.rejectTransfer(requestId);
        _;
    }

    function testApproveRevertsIfNotCurrentOwner() public productRegistered productRequested {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        vm.expectRevert(NexTrack.NexTrack__NotCurrentOwner.selector);
        vm.prank(USER);
        nexTrack.approveTransfer(requestId);
    }

    function testApproveRevertsIfRequestAlreadyApproved() public productRegistered productRequested transferApproved {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        vm.expectRevert(NexTrack.NexTrack__RequestAlreadyApproved.selector);
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.approveTransfer(requestId);
    }

    function testApproveRevertsIfRequestAlreadyRejected() public productRegistered productRequested transferRejected {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        vm.expectRevert(NexTrack.NexTrack__RequestAlreadyRejected.selector);
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.approveTransfer(requestId);
    }

    function testApproveRevertsIfRequestAlreadyCompleted() public productRegistered productRequested transferApproved {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        vm.prank(USER);
        nexTrack.confirmTransfer(requestId);
        vm.expectRevert(NexTrack.NexTrack__RequestAlreadyCompleted.selector);
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.approveTransfer(requestId);
    }

    function testApproveTransfer() public productRegistered productRequested {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.approveTransfer(requestId);
        NexTrack.TransferRequest memory requestDetails = nexTrack.getTransferRequestDetails(requestId);
        assertEq(uint8(requestDetails.status), uint8(NexTrack.RequestStatus.Approved));
    }

    function testApproveTransferEmitsEvent() public productRegistered productRequested {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        NexTrack.TransferRequest memory requestDetails = nexTrack.getTransferRequestDetails(requestId);
        uint256 batchId = requestDetails.batchId;
        vm.expectEmit(true, true, true, true, address(nexTrack));
        emit NexTrack.TransferApproved(requestId, batchId, USER, QUANTITY_TO_SHIP, block.timestamp);
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.approveTransfer(requestId);
    }

    ////////////////////////////////
    //// Reject Transfer Tests /////
    ////////////////////////////////

    function testRejectRevertsIfNotCurrentOwner() public productRegistered productRequested {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        vm.expectRevert(NexTrack.NexTrack__NotCurrentOwner.selector);
        vm.prank(USER);
        nexTrack.rejectTransfer(requestId);
    }

    function testRejectTransferRevertsIfRequestAlreadyApproved()
        public
        productRegistered
        productRequested
        transferApproved
    {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        vm.expectRevert(NexTrack.NexTrack__RequestAlreadyApproved.selector);
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.rejectTransfer(requestId);
    }

    function testRejectTransferRevertsIfRequestAlreadyRejected()
        public
        productRegistered
        productRequested
        transferRejected
    {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        vm.expectRevert(NexTrack.NexTrack__RequestAlreadyRejected.selector);
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.rejectTransfer(requestId);
    }

    function testRejectTransferRevertsIfRequestAlreadyCompleted()
        public
        productRegistered
        productRequested
        transferApproved
    {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        vm.prank(USER);
        nexTrack.confirmTransfer(requestId);
        vm.expectRevert(NexTrack.NexTrack__RequestAlreadyCompleted.selector);
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.rejectTransfer(requestId);
    }

    function testRejectTransfer() public productRegistered productRequested {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.rejectTransfer(requestId);
        NexTrack.TransferRequest memory requestDetails = nexTrack.getTransferRequestDetails(requestId);
        assertEq(uint8(requestDetails.status), uint8(NexTrack.RequestStatus.Rejected));
    }

    function testRejectTransferEmitsEvent() public productRegistered productRequested {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        NexTrack.TransferRequest memory requestDetails = nexTrack.getTransferRequestDetails(requestId);
        uint256 batchId = requestDetails.batchId;
        vm.expectEmit(true, true, true, true, address(nexTrack));
        emit NexTrack.TransferRejected(requestId, batchId, USER, QUANTITY_TO_SHIP, block.timestamp);
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.rejectTransfer(requestId);
    }

    ///////////////////////////////
    //// Confirm Transfer Tests ///
    ///////////////////////////////

    function testRevertsIfNotIntendedRecipient() public productRegistered productRequested transferApproved {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        vm.expectRevert(NexTrack.NexTrack__NotIntendedRecipient.selector);
        vm.prank(RANDOM_USER);
        nexTrack.confirmTransfer(requestId);
    }

    function testRevertsIfRequestStillPending() public productRegistered productRequested {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        vm.expectRevert(NexTrack.NexTrack__RequestStillPending.selector);
        vm.prank(USER);
        nexTrack.confirmTransfer(requestId);
    }

    function testRevertsIfRequestAlreadyRejected() public productRegistered productRequested transferRejected {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        vm.expectRevert(NexTrack.NexTrack__RequestAlreadyRejected.selector);
        vm.prank(USER);
        nexTrack.confirmTransfer(requestId);
    }

    function testRevertsIfRequestAlreadyCompleted() public productRegistered productRequested transferApproved {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        vm.prank(USER);
        nexTrack.confirmTransfer(requestId);

        // try to confirm the request again, should revert
        vm.prank(USER);
        vm.expectRevert(NexTrack.NexTrack__RequestAlreadyCompleted.selector);
        nexTrack.confirmTransfer(requestId);
    }

    function testConfirmTransfer() public productRegistered productRequested transferApproved {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        NexTrack.TransferRequest memory requestDetails = nexTrack.getTransferRequestDetails(requestId);
        uint256 parentBatchId = requestDetails.batchId;
        vm.prank(USER);
        (, uint256 newBatchId) = nexTrack.confirmTransfer(requestId);
        NexTrack.ProductBatch memory batchDetails = nexTrack.getBatchDetails(parentBatchId);

        // Assert parent batch
        assertEq(batchDetails.totalQuantity, TOTAL_QUANTITY - QUANTITY_TO_SHIP);
        assertEq(batchDetails.parentBatch, DEFAULT_BATCH_ID);

        NexTrack.ProductBatch memory newBatchDetails = nexTrack.getBatchDetails(newBatchId);

        // Assert child batch
        assertEq(newBatchDetails.owner, USER);
        assertEq(newBatchDetails.totalQuantity, QUANTITY_TO_SHIP);
        assertEq(newBatchDetails.parentBatch, parentBatchId);

        requestDetails = nexTrack.getTransferRequestDetails(requestId);

        // Assert request
        assertEq(uint8(requestDetails.status), uint8(NexTrack.RequestStatus.Completed));
    }

    function testEmitsEventOnTransferConfirmation() public productRegistered productRequested transferApproved {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        NexTrack.TransferRequest memory requestDetails = nexTrack.getTransferRequestDetails(requestId);
        uint256 parentBatchId = requestDetails.batchId;

        // Expect the first event: RequestCompleted
        vm.expectEmit(true, true, true, true, address(nexTrack));
        emit NexTrack.RequestCompleted(requestId, USER, block.timestamp);

        // Expect the second event: ReceivedAndCreatedBatch
        vm.expectEmit(true, true, true, true, address(nexTrack));
        emit NexTrack.ReceivedAndCreatedBatch(
            requestId,
            uint64(
                bytes8(
                    keccak256(abi.encodePacked(name, category, QUANTITY_TO_SHIP, parentBatchId, USER, block.timestamp))
                )
            ),
            name,
            description,
            category,
            USER,
            QUANTITY_TO_SHIP,
            parentBatchId,
            block.timestamp
        );
        vm.prank(USER);
        nexTrack.confirmTransfer(requestId);
    }
}
