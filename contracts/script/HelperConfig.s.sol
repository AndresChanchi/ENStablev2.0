// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title HelperConfig
 * @author Andres Chanchi
 * @notice Manages network-specific configurations for deployment and testing.
 * @dev Centralizes contract addresses like PoolManager and Agent wallets across chains.
 */

// --- Imports ---
import {Script} from "forge-std/Script.sol";

// --- Contracts ---
contract HelperConfig is Script {
    // --- Type Declarations ---
    struct NetworkConfig {
        address poolManager;
        address hook;
        address agentWallet;
    }

    // --- State Variables ---
    NetworkConfig public activeNetworkConfig;

    address public constant UNICHAIN_POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    uint256 public constant UNICHAIN_SEPOLIA_CHAIN_ID = 1301;

    // --- Functions ---

    constructor() {
        if (block.chainid == UNICHAIN_SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getUnichainSepoliaConfig();
        } else {
            // By default, we use the Unichain configuration.
            // This forces tests to run on a Fork to locate the PoolManager.
            activeNetworkConfig = getUnichainSepoliaConfig();
        }
    }

    /**
     * @notice Returns the configuration for the Unichain Sepolia network.
     */
    function getUnichainSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            poolManager: UNICHAIN_POOL_MANAGER,
            hook: address(0),
            agentWallet: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
        });
    }

    /**
     * @notice Maintains compatibility with existing scripts but redirects to Unichain config.
     */
    function getOrCreateAnvilEthConfig() public pure returns (NetworkConfig memory) {
        return getUnichainSepoliaConfig();
    }
}
