// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {NexTrack} from "../src/NexTrack.sol";

contract DeployNexTrack is Script {
    NexTrack public nexTrack;
    address[] public registeredManufacturers = [
        address(1),
        address(2),
        address(3),
        address(4),
        address(5),
        address(6),
        address(7),
        address(8),
        address(9),
        address(10)
    ];

    function run() external returns (NexTrack) {
        return deployNexTrack();
    }

    function deployNexTrack() public returns (NexTrack) {
        vm.startBroadcast();
        nexTrack = new NexTrack(registeredManufacturers);
        vm.stopBroadcast();
        return nexTrack;
    }
}
