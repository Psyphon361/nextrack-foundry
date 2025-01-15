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
        nexTrack.registerProduct(name, description, category, TOTAL_QUANTITY);
    }

    function testRegisterProduct() public {
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.registerProduct(name, description, category, TOTAL_QUANTITY);

        uint256 productId = nexTrack.getCurrentInventory(REGISTERED_MANUFACTURER)[0];
        NexTrack.ProductBatch memory productBatch = nexTrack.getProductDetails(productId);

        assertEq(productBatch.name, name);
        assertEq(productBatch.description, description);
        assertEq(uint8(productBatch.category), uint8(category));
        assertEq(productBatch.owner, REGISTERED_MANUFACTURER);
        assertEq(uint8(productBatch.status), uint8(NexTrack.Status.Manufactured));
        assertEq(productBatch.intendedRecipient, address(0));
    }

    function testEmitsEventOnProductRegistration() public {
        vm.expectEmit(true, true, true, true, address(nexTrack));
        emit NexTrack.ProductRegistered(
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
            NexTrack.Status.Manufactured,
            address(0),
            TOTAL_QUANTITY,
            DEFAULT_QUANTITY_TO_SHIP,
            DEFAULT_BATCH_ID,
            block.timestamp
        );
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.registerProduct(name, description, category, TOTAL_QUANTITY);
    }

    ////////////////////////////
    // Transfer Product Tests //
    ////////////////////////////

    modifier productRegistered() {
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.registerProduct(name, description, category, TOTAL_QUANTITY);
        _;
    }

    function testRevertsIfNotCurrentOwner() public productRegistered {
        uint256 productId = nexTrack.getCurrentInventory(REGISTERED_MANUFACTURER)[0];
        vm.expectRevert(NexTrack.NexTrack__NotCurrentOwner.selector);
        vm.prank(USER);
        nexTrack.initiateTransfer(productId, USER, QUANTITY_TO_SHIP);
    }

    function testInitiateTransfer() public productRegistered {
        uint256 productId = nexTrack.getCurrentInventory(REGISTERED_MANUFACTURER)[0];
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.initiateTransfer(productId, USER, QUANTITY_TO_SHIP);

        NexTrack.ProductBatch memory batchDetails = nexTrack.getProductDetails(productId);
        assertEq(uint8(batchDetails.status), uint8(NexTrack.Status.InTransit));
        assertEq(batchDetails.intendedRecipient, USER);
        assertEq(batchDetails.quantityToShip, QUANTITY_TO_SHIP);
    }

    function testEmitsEventOnTransferInitiation() public productRegistered {
        uint256 productId = nexTrack.getCurrentInventory(REGISTERED_MANUFACTURER)[0];
        vm.expectEmit(true, true, true, false, address(nexTrack));
        emit NexTrack.TransferInitiated(productId, USER, QUANTITY_TO_SHIP, block.timestamp);
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.initiateTransfer(productId, USER, QUANTITY_TO_SHIP);
    }

    ////////////////////////////
    // Confirm Receipt Tests ///
    ////////////////////////////

    modifier transferInitiated() {
        uint256 batchId = nexTrack.getCurrentInventory(REGISTERED_MANUFACTURER)[0];
        NexTrack.ProductBatch memory batch = nexTrack.getProductDetails(batchId);
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.initiateTransfer(batchId, USER, QUANTITY_TO_SHIP);
        _;
    }

    function testRevertsIfNotIntendedRecipient() public productRegistered transferInitiated {
        uint256 batchId = nexTrack.getCurrentInventory(REGISTERED_MANUFACTURER)[0];
        vm.expectRevert(NexTrack.NexTrack__NotIntendedRecipient.selector);
        vm.prank(RANDOM_USER);
        nexTrack.confirmTransfer(batchId);
    }

    function testConfirmTransfer() public productRegistered transferInitiated {
        uint256 parentBatchId = nexTrack.getCurrentInventory(REGISTERED_MANUFACTURER)[0];
        vm.prank(USER);
        uint256 newBatchId = nexTrack.confirmTransfer(parentBatchId);
 
        NexTrack.ProductBatch memory batchDetails = nexTrack.getProductDetails(parentBatchId);

        // Assert parent batch
        assertEq(uint8(batchDetails.status), uint8(NexTrack.Status.Manufactured));
        assertEq(batchDetails.intendedRecipient, address(0));
        assertEq(batchDetails.totalQuantity, TOTAL_QUANTITY - QUANTITY_TO_SHIP);
        assertEq(batchDetails.quantityToShip, 0);
        assertEq(batchDetails.parentBatch, DEFAULT_BATCH_ID);

        NexTrack.ProductBatch memory newBatchDetails = nexTrack.getProductDetails(newBatchId);

        // Assert child batch
        assertEq(newBatchDetails.owner, USER);
        assertEq(uint8(newBatchDetails.status), uint8(NexTrack.Status.InWarehouse));
        assertEq(newBatchDetails.intendedRecipient, address(0));
        assertEq(newBatchDetails.totalQuantity, QUANTITY_TO_SHIP);
        assertEq(newBatchDetails.quantityToShip, 0);
        assertEq(newBatchDetails.parentBatch, parentBatchId);
    }

    function testEmitsEventOnTransferConfirmation() public productRegistered transferInitiated {
        uint256 parentBatchId = nexTrack.getCurrentInventory(REGISTERED_MANUFACTURER)[0];
        vm.expectEmit(true, true, true, true, address(nexTrack));
        emit NexTrack.ReceivedAndCreatedBatch(uint64(
            bytes8(
                keccak256(abi.encodePacked(name, category, QUANTITY_TO_SHIP, parentBatchId, USER, block.timestamp))
            )
        ), name, description, category, USER, NexTrack.Status.InWarehouse, address(0), QUANTITY_TO_SHIP, 0, parentBatchId, block.timestamp);
        vm.prank(USER);
        nexTrack.confirmTransfer(parentBatchId);
    }
}
