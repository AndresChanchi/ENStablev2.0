// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console} from "forge-std/Script.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {HookMiner} from "../src/libraries/HookMiner.sol";
import {EnstableHook} from "../src/core/EnstableHook.sol";
import {IdentityVault} from "../src/core/IdentityVault.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployFullSystem is Script {
    function run() external returns (EnstableHook hook, IdentityVault vault, IPoolManager poolManager) {
        HelperConfig helperConfig = new HelperConfig();
        (address poolManagerAddr,, address agent) = helperConfig.activeNetworkConfig();
        poolManager = IPoolManager(poolManagerAddr);

        address deployer = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        vm.deal(deployer, 10 ether);

        vm.startBroadcast(deployer);

        uint256 nonce = vm.getNonce(deployer);
        address predictedVault = vm.computeCreateAddress(deployer, nonce + 1);

        uint160 flags =
            uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG);

        bytes memory constructorArgs = abi.encode(poolManagerAddr, predictedVault, agent);

        (address hookAddress, bytes32 salt) = HookMiner.find(
            0x4e59b44847b379578588920cA78FbF26c0B4956C, flags, type(EnstableHook).creationCode, constructorArgs
        );

        hook = new EnstableHook{salt: salt}(poolManager, predictedVault, agent);
        vault = new IdentityVault(poolManagerAddr, address(hook));

        vm.stopBroadcast();
        _printSummary(address(hook), address(vault), predictedVault);
    }

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
