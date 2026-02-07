// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title DeployIdentityVault
 * @author Andres Chanchi
 * @notice Script for standalone deployment of the IdentityVault.
 */

// Imports
import {Script} from "forge-std/Script.sol";
import {IdentityVault} from "../src/core/IdentityVault.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

// Interfaces, Libraries, Contracts
contract DeployIdentityVault is Script {
    // Functions

    /**
     * @notice Deploys the IdentityVault using parameters from HelperConfig.
     * @return vault The deployed IdentityVault contract instance.
     * @return helperConfig The configuration helper used for deployment.
     */
    function run() external returns (IdentityVault, HelperConfig) {
        // 1. Setup Configuration
        HelperConfig helperConfig = new HelperConfig();
        (address poolManager, address hook,) = helperConfig.activeNetworkConfig();

        // 2. Broadcast Deployment
        vm.startBroadcast();
        IdentityVault vault = new IdentityVault(poolManager, hook);
        vm.stopBroadcast();

        return (vault, helperConfig);
    }
}
