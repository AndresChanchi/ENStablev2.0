// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title DeployFullSystem
 * @author Andres Chanchi
 * @notice Script to deploy the EnstableHook and IdentityVault with correct Uniswap v4 flags.
 * @dev Uses HookMiner to find a salt that satisfies the required hook flags.
 */

// --- Imports ---
import {Script, console} from "forge-std/Script.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {HookMiner} from "../src/libraries/HookMiner.sol";
import {EnstableHook} from "../src/core/EnstableHook.sol";
import {IdentityVault} from "../src/core/IdentityVault.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

// --- Contracts ---
contract DeployFullSystem is Script {
    /**
     * @notice Deploys the full system and validates the predicted vault address.
     * @return hook The deployed EnstableHook contract.
     * @return vault The deployed IdentityVault contract.
     * @return poolManager The Uniswap v4 PoolManager interface.
     */
    function run() external returns (EnstableHook hook, IdentityVault vault, IPoolManager poolManager) {
        // 1. Setup Configuration
        HelperConfig helperConfig = new HelperConfig();
        (address poolManagerAddr,, address agent) = helperConfig.activeNetworkConfig();
        poolManager = IPoolManager(poolManagerAddr);

        address deployer = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        vm.deal(deployer, 10 ether);

        vm.startBroadcast(deployer);

        // 2. Predict Vault Address (Deployed after Hook, so nonce + 1)
        uint256 nonce = vm.getNonce(deployer);
        address predictedVault = vm.computeCreateAddress(deployer, nonce + 1);

        // 3. Define Hook Flags (Required for v4 PoolManager)
        uint160 flags =
            uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG);

        // 4. Find Salt for Hook Deployment
        bytes memory constructorArgs = abi.encode(poolManagerAddr, predictedVault, agent);

        // FIX: Removed unused 'hookAddress' to solve Warning (2072)
        (, bytes32 salt) = HookMiner.find(
            0x4e59b44847b379578588920cA78FbF26c0B4956C, // CREATE2 Factory
            flags,
            type(EnstableHook).creationCode,
            constructorArgs
        );

        // 5. Deploy Contracts
        hook = new EnstableHook{salt: salt}(poolManager, predictedVault, agent);
        vault = new IdentityVault(poolManagerAddr, address(hook));

        vm.stopBroadcast();

        // 6. Validation Summary
        _printSummary(address(hook), address(vault), predictedVault);
    }

    /**
     * @dev Internal helper to log deployment details and verify address consistency.
     */
    function _printSummary(address hook, address vault, address predicted) internal pure {
        console.log("--- DEPLOYMENT SUCCESS ---");
        console.log("Hook Address:          ", hook);
        console.log("Vault Address:         ", vault);
        console.log("Predicted Match:       ", vault == predicted);

        if (vault != predicted) {
            revert("CRITICAL: Vault address mismatch! Hook is pointing to a dead address.");
        }
    }
}
