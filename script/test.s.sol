// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {GovToken} from "../src/governance/GovToken.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract Test is Script {
    uint256 public deployerKey;

    function run() external returns(GovToken) {
        return deployGovToken();
    }

    function deployGovToken() public returns(GovToken) {
        HelperConfig config = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = config.getActiveNetworkConfig();
        deployerKey = networkConfig.deployerKey;

        vm.startBroadcast(deployerKey);
        GovToken govToken = new GovToken();
        vm.stopBroadcast();
        console.log("Governance token deployed at:", address(govToken));
        return govToken;
    }
}