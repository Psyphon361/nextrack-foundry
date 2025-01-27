// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {DeployNexTrack} from "../script/DeployNexTrack.s.sol";
import {NexTrack} from "../src/NexTrack.sol";
import {MyGovernor} from "../src/governance/MyGovernor.sol";
import {GovToken} from "../src/governance/GovToken.sol";
import {Vault} from "../src/Vault.sol";
import {USDTMock} from "../src/USDTMock.sol";

contract NexTrackTest is Test {
    DeployNexTrack public deployer;
    NexTrack public nexTrack;
    MyGovernor public governor;
    GovToken public govToken;
    Vault public vault;
    USDTMock public usdt;

    address public USER = makeAddr("user");
    address public RANDOM_USER = makeAddr("random_user");
    address public REGISTERED_MANUFACTURER = address(1);
    address public SECOND_REGISTERED_MANUFACTURER = address(2);
    address public DEFAULT_ANVIL_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    string public name = "Earphones";
    string public productDescription = "High quality earphones";
    NexTrack.Category public category = NexTrack.Category.Electronics;
    uint256 public TOTAL_QUANTITY = 100;
    uint256 public QUANTITY_TO_SHIP = 30;
    uint256 public UNIT_PRICE = 2;
    uint256 public PRECISION = 1e18;

    uint256 public constant DEFAULT_BATCH_ID = 0;
    uint256 public constant DEFAULT_QUANTITY_TO_SHIP = 0;

    uint256 public constant MIN_DELAY = 3600; // 1hr - after a vote passes
    uint256 public constant VOTING_DELAY = 17280; // number of blocks till a vote is active - 1 day in this case for 5 second block times
    uint256 public constant VOTING_PERIOD = 120960; // number of weeks the vote is open - 7 days

    uint256[] values;
    bytes[] calldatas;
    address[] targets;

    ///////////////////////
    /// SetUp Function ////
    ///////////////////////

    function setUp() public {
        deployer = new DeployNexTrack();
        (nexTrack, governor, govToken, vault, usdt) = deployer.run();
        console2.log("NexTrack Address: ", address(nexTrack));

        // mint and approve USDT spend for USER
        vm.prank(DEFAULT_ANVIL_ACCOUNT);
        usdt.mint(USER, 1e18);
        vm.prank(USER);
        usdt.approve(address(vault), 1e18);

        // delegate voting power
        vm.prank(REGISTERED_MANUFACTURER);
        govToken.delegate(REGISTERED_MANUFACTURER);
        vm.prank(SECOND_REGISTERED_MANUFACTURER);
        govToken.delegate(SECOND_REGISTERED_MANUFACTURER);

        // add initial set of manufacturers and transfer ownership of NexTrack to TimeLock
        vm.startPrank(DEFAULT_ANVIL_ACCOUNT);
        nexTrack.onboardInitialManufacturers();
        nexTrack.transferOwnershipToTimelock();
        vm.stopPrank();
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////

    function testContractDeployment() public view {
        // console2.log("NexTrack Address: ", address(nexTrack));
        assert(address(nexTrack) != address(0));

        uint256 manufacturerCount = nexTrack.getManufacturerCount();
        // console2.log("Manufacturer Count: ", manufacturerCount);

        assertEq(manufacturerCount, 5);
    }

    ////////////////////////////
    // Register Product Tests //
    ////////////////////////////

    function testRevertsIfNotRegisteredManufacturer() public {
        vm.expectRevert(NexTrack.NexTrack__NotRegisteredManufacturer.selector);
        vm.prank(USER);
        nexTrack.registerProductBatch(name, productDescription, category, TOTAL_QUANTITY, UNIT_PRICE);
    }

    function testRegisterProduct() public {
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.registerProductBatch(name, productDescription, category, TOTAL_QUANTITY, UNIT_PRICE);

        uint256 batchId = nexTrack.getCurrentInventory(REGISTERED_MANUFACTURER)[0];
        NexTrack.ProductBatch memory productBatch = nexTrack.getBatchDetails(batchId);

        assertEq(productBatch.name, name);
        assertEq(productBatch.description, productDescription);
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
            productDescription,
            category,
            REGISTERED_MANUFACTURER,
            TOTAL_QUANTITY,
            UNIT_PRICE,
            DEFAULT_BATCH_ID,
            block.timestamp
        );
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.registerProductBatch(name, productDescription, category, TOTAL_QUANTITY, UNIT_PRICE);
    }

    ////////////////////////////
    // Request Product Tests ///
    ////////////////////////////

    modifier productRegistered() {
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.registerProductBatch(name, productDescription, category, TOTAL_QUANTITY, UNIT_PRICE);
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
        emit NexTrack.ProductBatchRequested(
            uint64(
                bytes8(keccak256(abi.encodePacked(batchId, REGISTERED_MANUFACTURER, QUANTITY_TO_SHIP, block.timestamp)))
            ),
            batchId,
            REGISTERED_MANUFACTURER,
            USER,
            QUANTITY_TO_SHIP,
            UNIT_PRICE * QUANTITY_TO_SHIP,
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
            productDescription,
            category,
            USER,
            QUANTITY_TO_SHIP,
            UNIT_PRICE,
            parentBatchId,
            block.timestamp
        );
        vm.prank(USER);
        nexTrack.confirmTransfer(requestId);
    }

    /*//////////////////////////////
            Governance Tests
    //////////////////////////////*/

    function testCannotOnboardManufacturerWithoutGovernance() public {
        vm.expectRevert();
        nexTrack.onboardNewManufacturer(USER);
    }

    function testGovernanceOnboardsNewManufacturer() public {
        address newManufacturer = address(6);
        string memory description = "Onboard new manufacturer to the system";
        bytes memory encodedFunctionCall = abi.encodeWithSignature("onboardNewManufacturer(address)", newManufacturer);
        values.push(0);
        calldatas.push(encodedFunctionCall);
        targets.push(address(nexTrack));

        console2.log("Governance token supply before proposal: ", govToken.totalSupply());

        // 1. Propose to DAO
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // View the proposal state
        console2.log("Proposal state before voting delay: ", uint256(governor.state(proposalId)));

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        console2.log("Proposal state after voting delay: ", uint256(governor.state(proposalId)));

        // 2. Vote on the proposal
        string memory reason = "cuz this manufacturer is cool";
        uint8 voteWay = 1; // voting yes (in favor of proposal)

        // first vote
        vm.prank(REGISTERED_MANUFACTURER);
        governor.castVoteWithReason(proposalId, voteWay, reason);

        // second vote
        vm.prank(SECOND_REGISTERED_MANUFACTURER);
        governor.castVoteWithReason(proposalId, voteWay, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        console2.log("Proposal state after voting: ", uint256(governor.state(proposalId)));

        // 3. Queue the TX
        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        console2.log("Governance token supply before: ", govToken.totalSupply());

        address[] memory registeredManufacturers1 = nexTrack.getRegisteredManufacturers();
        for (uint256 i = 0; i < registeredManufacturers1.length; i++) {
            console2.log("Registered manufacturer ", i, ":", registeredManufacturers1[i]);
        }
        // 4. Execute
        governor.execute(targets, values, calldatas, descriptionHash);

        address[] memory registeredManufacturers = nexTrack.getRegisteredManufacturers();
        console2.log("Governance token supply after execution: ", govToken.totalSupply());

        for (uint256 i = 0; i < registeredManufacturers.length; i++) {
            console2.log("Registered manufacturer ", i, ":", registeredManufacturers[i]);
        }

        assertEq(govToken.totalSupply() / PRECISION, nexTrack.getRegisteredManufacturers().length);
        assertEq(newManufacturer, registeredManufacturers[registeredManufacturers.length - 1]);
    }

    function testQueueFunctionRevertsIfVoteNotPassed() public {
        address newManufacturer = address(11);
        string memory description = "Onboard new manufacturer to the system";
        bytes memory encodedFunctionCall = abi.encodeWithSignature("onboardNewManufacturer(address)", newManufacturer);
        values.push(0);
        calldatas.push(encodedFunctionCall);
        targets.push(address(nexTrack));
        // 1. Propose to DAO
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);
        // 2. Vote on the proposal
        string memory reason = "cuz this manufacturer is cool";
        uint8 voteWay = 1; // voting yes (in favor of proposal)
        // only one vote
        vm.prank(REGISTERED_MANUFACTURER);
        governor.castVoteWithReason(proposalId, voteWay, reason);
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);
        // 3. Queue the TX
        bytes32 descriptionHash = keccak256(bytes(description));
        vm.expectRevert();
        governor.queue(targets, values, calldatas, descriptionHash);
    }

    /*//////////////////////////////
            Vault Tests
    //////////////////////////////*/

    function testUSDTDepositOnNewRequest() public productRegistered productRequested {
        uint256 vaultBalance = usdt.balanceOf(address(vault));
        // console2.log("Vault balance: ", vaultBalance);
        assertEq(vaultBalance, QUANTITY_TO_SHIP * UNIT_PRICE);
    }

    function testUSDTRefundOnRejectRequest() public productRegistered productRequested {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        uint256 vaultBalanceBefore = usdt.balanceOf(address(vault));
        uint256 userBalanceBefore = usdt.balanceOf(USER);
        assertEq(vaultBalanceBefore, QUANTITY_TO_SHIP * UNIT_PRICE);
        vm.prank(REGISTERED_MANUFACTURER);
        nexTrack.rejectTransfer(requestId);
        uint256 vaultBalanceAfter = usdt.balanceOf(address(vault));
        uint256 userBalanceAfter = usdt.balanceOf(USER);
        assertEq(vaultBalanceAfter, 0);
        assertEq(userBalanceAfter, userBalanceBefore + QUANTITY_TO_SHIP * UNIT_PRICE);
    }

    function testUSDTWithdrawOnConfirmRequest() public productRegistered productRequested transferApproved {
        uint256 requestId = nexTrack.getSellerTransferRequests(REGISTERED_MANUFACTURER)[0];
        uint256 vaultBalanceBefore = usdt.balanceOf(address(vault));
        console2.log("Vault balance before confirm: ", vaultBalanceBefore);
        vm.prank(USER);
        nexTrack.confirmTransfer(requestId);
        uint256 vaultBalanceAfter = usdt.balanceOf(address(vault));
        assertEq(vaultBalanceAfter, 0);
        uint256 userBalanceAfter = usdt.balanceOf(REGISTERED_MANUFACTURER);
        assertEq(userBalanceAfter, vaultBalanceBefore);
    }

    function testRevertsIfTriesToDepositAgainForTheSameRequest() public productRegistered productRequested {
        uint256 batchId = nexTrack.getCurrentInventory(REGISTERED_MANUFACTURER)[0];
        vm.prank(USER);
        vm.expectRevert(Vault.Vault__CannotDepositAgain.selector);
        nexTrack.requestProductBatch(batchId, REGISTERED_MANUFACTURER, QUANTITY_TO_SHIP);
    }

    function testGetUsdtAddress() public view {
        address usdtAddress = vault.getUsdtAddress();
        assertEq(usdtAddress, address(usdt));
    }
}
