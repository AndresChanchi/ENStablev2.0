// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title DeployFullSystem
 * @author Andres Chanchi
 * @notice Script to deploy the Enstable Hook and Identity Vault with CREATE2 address mining.
 * @dev Pre-computes the Vault address to solve the circular dependency with the Hook.
 */

// Imports
import {Script, console} from "forge-std/Script.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {HookMiner} from "../src/libraries/HookMiner.sol";
import {EnstableHook} from "../src/core/EnstableHook.sol";
import {IdentityVault} from "../src/core/IdentityVault.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

// Interfaces, Libraries, Contracts
contract DeployFullSystem is Script {
    // Functions

    /**
     * @notice Main execution function for the deployment script.
     */
    function run() external {
        // 1. Setup Configuration
        HelperConfig helperConfig = new HelperConfig();
        (address poolManagerAddr,, address agent) = helperConfig.activeNetworkConfig();
        IPoolManager poolManager = IPoolManager(poolManagerAddr);

        // Deployment parameters
        address deployer = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        uint256 nonce = vm.getNonce(deployer);

        // 2. Pre-computation Phase
        // We predict the Vault address (Nonce + 1 because the Hook is deployed first)
        address predictedVault = vm.computeCreateAddress(deployer, nonce + 1);

        // Hook Flag Configuration for Uniswap V4
        uint160 flags =
            uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG);

        bytes memory constructorArgs = abi.encode(poolManagerAddr, predictedVault, agent);

        // 3. Mining Phase
        console.log("Mining Hook salt for required flags...");
        (address hookAddress, bytes32 salt) = HookMiner.find(
            0x4e59b44847b379578588920cA78FbF26c0B4956C, // Canonical CREATE2 Deployer
            flags,
            type(EnstableHook).creationCode,
            constructorArgs
        );
        console.log("Target Hook Address:", hookAddress);

        // 4. Broadcast Phase (On-chain Transactions)
        vm.startBroadcast();

        // Transaction 1: Deploy the Brain (EnstableHook)
        EnstableHook hook = new EnstableHook{salt: salt}(poolManager, predictedVault, agent);

        // Transaction 2: Deploy the Actuator (IdentityVault)
        IdentityVault vault = new IdentityVault(poolManagerAddr, address(hook));

        vm.stopBroadcast();

        // 5. Validation & Logging
        _printSummary(address(hook), address(vault), predictedVault);
    }

    // Internal & Private View & Pure Functions
    /**
     * @dev Simple helper to print deployment results to the console.
     */
    function _printSummary(address hook, address vault, address predicted) internal pure {
        console.log("--- DEPLOYMENT SUCCESS ---");
        console.log("Hook Address:          ", hook);
        console.log("Vault Address:         ", vault);
        console.log("Predicted Vault Match: ", vault == predicted);
    }
}
