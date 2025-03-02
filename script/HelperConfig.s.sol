// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address[] registeredManufacturers;
        uint256 deployerKey;
    }

    address[] public anvilRegisteredManufacturers = [address(1), address(2), address(3), address(4), address(5)];
    address[] public electroneumRegisteredManufacturers = [
        0x779575dc32b4BDC36Ef56f2041AA6E42024AF88D,
        0x5Ddf1fb5F08feB33bee022FAbB7918E67e242b38,
        0x5c8adA8E4C007E89cA6D3ab85d7029eD8a71D3C5,
        0x474Ee01D208864C6b9e63e595A924F55d0E5fF89,
        0xCd0b706556289b539fFB8a840bEc3FD8e55fdbb7
    ];
    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    NetworkConfig private activeNetworkConfig;

    constructor() {
        if (block.chainid == 5201420 || block.chainid == 52014 || block.chainid == 11155111 || block.chainid == 943) {
            activeNetworkConfig = getElectroneumConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getElectroneumConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            registeredManufacturers: electroneumRegisteredManufacturers,
            deployerKey: /*vm.envUint("PRIVATE_KEY")*/ 0
        });
    }

    function getOrCreateAnvilEthConfig() public view returns (NetworkConfig memory) {
        if (activeNetworkConfig.registeredManufacturers.length > 0) {
            return activeNetworkConfig;
        }

        return NetworkConfig({registeredManufacturers: anvilRegisteredManufacturers, deployerKey: DEFAULT_ANVIL_KEY});
    }

    function getActiveNetworkConfig() external view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}
