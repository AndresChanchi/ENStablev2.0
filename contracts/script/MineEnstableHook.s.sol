// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title MineEnstableHook
 * @author Andres Chanchi
 * @notice Utility script to find a salt for a CREATE2 deployment of the EnstableHook.
 * @dev Finds a salt that results in a hook address satisfying Uniswap v4 flag requirements.
 */

// Imports
import {Script, console} from "forge-std/Script.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "../src/libraries/HookMiner.sol";
import {EnstableHook} from "../src/core/EnstableHook.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

// Interfaces, Libraries, Contracts
contract MineEnstableHook is Script {
    // State Variables
    // Canonical CREATE2 Deployer Proxy (Deterministic across most EVM networks)
    address private constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // Functions

    /**
     * @notice Runs the salt mining process.
     */
    function run() external {
        // 1. Load System Configuration
        HelperConfig helperConfig = new HelperConfig();
        (address poolManager,, address agent) = helperConfig.activeNetworkConfig();

        // 2. Predict Vault Address
        // The deployer address must match the one used in your Makefile/deployment environment
        address deployerAddress = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        uint256 nonce = vm.getNonce(deployerAddress);

        /**
         * @dev Address prediction logic:
         * If the Vault is deployed as the first transaction of the deployer, use 'nonce'.
         * If the Vault follows the Hook deployment, use 'nonce + 1'.
         */
        address predictedVault = vm.computeCreateAddress(deployerAddress, nonce);

        // 3. Configure Hook Flags
        // These flags must match the permissions defined in getHookPermissions()
        uint160 flags =
            uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG);

        // 4. Prepare Mining Arguments
        // These must match the EnstableHook constructor exactly
        bytes memory constructorArgs = abi.encode(poolManager, predictedVault, agent);

        _logMiningStart(deployerAddress, nonce, predictedVault);

        // 5. Execute Mining
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(EnstableHook).creationCode, constructorArgs);

        _logMiningResult(salt, hookAddress, predictedVault);
    }

    // Internal & Private View & Pure Functions

    /**
     * @dev Prints initial search parameters to the console.
     */
    function _logMiningStart(address deployer, uint256 nonce, address predicted) internal pure {
        console.log("--- STARTING HOOK MINING ---");
        console.log("Deployer Address:        ", deployer);
        console.log("Current Nonce:           ", nonce);
        console.log("Predicted Vault Address: ", predicted);
        console.log("Mining for salt... (This may take a moment)");
    }

    /**
     * @dev Prints the mining result and critical deployment warnings.
     */
    function _logMiningResult(bytes32 salt, address hook, address vault) internal pure {
        console.log("--- MINING COMPLETE ---");
        console.log("Salt:         ", vm.toString(salt));
        console.log("Hook Address: ", hook);
        console.log("-----------------------");
        console.log("CRITICAL: For the hook to function, the Vault MUST be");
        console.log("successfully deployed at:", vault);
    }
}
