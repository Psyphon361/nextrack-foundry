// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {NexTrack} from "../src/NexTrack.sol";
import {GovToken} from "../src/governance/GovToken.sol";
import {MyGovernor} from "../src/governance/MyGovernor.sol";
import {TimeLock} from "../src/governance/TimeLock.sol";
import {Vault} from "../src/Vault.sol";
import {USDTMock} from "../src/USDTMock.sol";

contract DeployNexTrack is Script {
    NexTrack public nexTrack;
    GovToken public govToken;
    MyGovernor public governor;
    TimeLock public timelock;
    Vault public vault;
    USDTMock public usdt;

    address[] proposers;
    address[] executors;
    address USDTOwner = makeAddr("usdtowner");

    uint256 public constant MIN_DELAY = 3600; // 1hr - after a vote passes
    uint256 public constant VOTING_DELAY = 1; // how many blocks till a vote is active
    uint256 public constant VOTING_PERIOD = 50400;

    address[] public registeredManufacturers = [address(1), address(2), address(3), address(4), address(5)];

    function run() external returns (NexTrack, MyGovernor, GovToken, Vault, USDTMock) {
        return deployNexTrack();
    }

    function deployNexTrack() public returns (NexTrack, MyGovernor, GovToken, Vault, USDTMock) {
        vm.startBroadcast();

        // deploy governance token contract
        govToken = new GovToken();
        for (uint256 i = 0; i < registeredManufacturers.length; i++) {
            govToken.mint(registeredManufacturers[i], 1);
        }
        console.log("Governance token deployed at:", address(govToken));

        // deploy timelock contract
        timelock = new TimeLock(MIN_DELAY, proposers, executors);
        console.log("Timelock deployed at:", address(timelock));

        // deploy governor contract
        governor = new MyGovernor(govToken, timelock);
        console.log("Governor deployed at:", address(governor));

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();

        // set roles
        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));

        // deploy mock USDT contract
        usdt = new USDTMock();

        // deploy vault contract
        vault = new Vault(address(usdt));

        // deploy nexTrack contract
        nexTrack = new NexTrack(registeredManufacturers, govToken, vault);
        console.log("NexTrack deployed at:", address(nexTrack));

        console.log("NexTrack owner before:", nexTrack.owner());

        usdt.transferOwnership(USDTOwner);
        vault.transferOwnership(address(nexTrack));
        nexTrack.transferOwnership(address(timelock));

        console.log("NexTrack owner after:", nexTrack.owner());
        console.log("USDT Owner: ", usdt.owner());

        vm.stopBroadcast();
        console.log("Deploy success!!!");
        return (nexTrack, governor, govToken, vault, usdt);
    }
}
