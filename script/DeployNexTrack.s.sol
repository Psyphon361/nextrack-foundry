// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {NexTrack} from "../src/NexTrack.sol";
import {GovToken} from "../src/governance/GovToken.sol";
import {MyGovernor} from "../src/governance/MyGovernor.sol";
import {TimeLock} from "../src/governance/TimeLock.sol";
import {Vault} from "../src/Vault.sol";
import {USDTMock} from "../src/USDTMock.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployNexTrack is Script {
    NexTrack public nexTrack;
    GovToken public govToken;
    MyGovernor public governor;
    TimeLock public timelock;
    Vault public vault;
    USDTMock public usdt;

    address[] proposers;
    address[] executors;

    uint256 public constant MIN_DELAY = 3600; // 1hr - after a vote passes
    uint256 public constant VOTING_DELAY = 1; // how many blocks till a vote is active
    uint256 public constant VOTING_PERIOD = 50400;
    uint256 public constant PRECISION = 1e18;

    address[] public registeredManufacturers;
    uint256 public deployerKey;

    function run() external returns (NexTrack, MyGovernor, GovToken, Vault, USDTMock) {
        return deployNexTrack();
    }

    function deployNexTrack() public returns (NexTrack, MyGovernor, GovToken, Vault, USDTMock) {
        HelperConfig config = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = config.getActiveNetworkConfig();

        registeredManufacturers = networkConfig.registeredManufacturers;
        deployerKey = networkConfig.deployerKey;

        vm.startBroadcast(deployerKey);

        // deploy governance token contract
        govToken = new GovToken();
        for (uint256 i = 0; i < registeredManufacturers.length; i++) {
            govToken.mint(registeredManufacturers[i], 1 * PRECISION);
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
        nexTrack = new NexTrack(registeredManufacturers, govToken, vault, timelock);
        console.log("NexTrack deployed at:", address(nexTrack));
        console.log("NexTrack owner before:", nexTrack.owner());

        vault.transferOwnership(address(nexTrack));
        nexTrack.transferOwnership(address(timelock));

        vm.stopBroadcast();

        console.log("NexTrack owner after:", nexTrack.owner());
        console.log("USDT Owner: ", usdt.owner());
        console.log("Deploy success!!!");
        return (nexTrack, governor, govToken, vault, usdt);
    }
}