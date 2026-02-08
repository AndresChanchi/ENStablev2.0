// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {EnstableHook} from "../src/core/EnstableHook.sol";
import {IdentityVault} from "../src/core/IdentityVault.sol";
import {HookMiner} from "../src/libraries/HookMiner.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {stdJson} from "forge-std/StdJson.sol"; // Para guardar el log

contract DeployAll is Script {
    using stdJson for string;

    function run() external {
        address agent = vm.envAddress("AGENT_ADDRESS");
        address poolManager = vm.envAddress("UNICHAIN_POOL_MANAGER");
        address create2Factory = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

        vm.startBroadcast();

        MockERC20 eusd = new MockERC20("Enstable Dollar", "EUSD");
        MockERC20 eeth = new MockERC20("Enstable Ether", "EETH");

        uint256 vaultNonce = vm.getNonce(msg.sender) + 1;
        address predictedVault = vm.computeCreateAddress(msg.sender, vaultNonce);

        uint160 flags =
            uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG);

        bytes memory constructorArgs = abi.encode(poolManager, predictedVault, agent);
        (, bytes32 salt) = HookMiner.find(create2Factory, flags, type(EnstableHook).creationCode, constructorArgs);

        EnstableHook hook = new EnstableHook{salt: salt}(IPoolManager(poolManager), predictedVault, agent);
        IdentityVault vault = new IdentityVault(poolManager, address(hook));

        eusd.mint(msg.sender, 10000 ether);
        eeth.mint(msg.sender, 10000 ether);
        vault.allowToken(address(eusd));
        vault.allowToken(address(eeth));

        vm.stopBroadcast();

        // --- REGISTRO AUTOMÁTICO EN ARCHIVO ---
        _saveDeployment(address(eusd), address(eeth), address(hook), address(vault));
        _printFinalSummary(address(eusd), address(eeth), address(hook), address(vault), agent);
    }

    function _saveDeployment(address eusd, address eeth, address hook, address vault) internal {
        string memory obj = "log";
        vm.serializeAddress(obj, "token0", eusd);
        vm.serializeAddress(obj, "token1", eeth);
        vm.serializeAddress(obj, "hook", hook);
        string memory finalJson = vm.serializeAddress(obj, "vault", vault);

        // Guarda un archivo JSON en la raíz para tu frontend
        vm.writeFile("deployments.json", finalJson);
        console.log("\n[INFO]: Direcciones guardadas en deployments.json");
    }

    function _printFinalSummary(address t0, address t1, address h, address v, address a) internal pure {
        console.log("--- DEPLOYMENT COMPLETE (UNICHAN SEPOLIA) ---");
        console.log("Token EUSD (Mock): ", t0);
        console.log("Token EETH (Mock): ", t1);
        console.log("Hook Address:      ", h);
        console.log("Vault Address:     ", v);
        console.log("Agente IA Auth:    ", a);
    }
}
