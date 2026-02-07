// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title HelperConfig
 * @author Andres Chanchi
 * @notice Manages network-specific configurations for deployment and testing.
 * @dev Centralizes contract addresses like PoolManager and Agent wallets across chains.
 */

// Imports
import {Script} from "forge-std/Script.sol";

// Interfaces, Libraries, Contracts
contract HelperConfig is Script {
    // Type Declarations
    struct NetworkConfig {
        address poolManager;
        address hook;
        address agentWallet;
    }

    // State Variables
    NetworkConfig public activeNetworkConfig;

    // Constants
    // Unichain Sepolia PoolManager Address
    address public constant UNICHAIN_POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    uint256 public constant UNICHAIN_SEPOLIA_CHAIN_ID = 1301;

    // Functions

    constructor() {
        if (block.chainid == UNICHAIN_SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getUnichainSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    // External & Public View & Pure Functions

    /**
     * @notice Returns configuration for Unichain Sepolia testnet.
     */
    function getUnichainSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            poolManager: UNICHAIN_POOL_MANAGER,
            hook: address(0), // To be updated after mining
            agentWallet: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
        });
    }

    /**
     * @notice Returns configuration for local Anvil environment.
     * @dev Defaults to Unichain addresses if no local state is found.
     */
    function getOrCreateAnvilEthConfig() public view returns (NetworkConfig memory) {
        if (activeNetworkConfig.poolManager != address(0)) {
            return activeNetworkConfig;
        }

        return NetworkConfig({
            poolManager: UNICHAIN_POOL_MANAGER,
            hook: address(0),
            agentWallet: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
        });
    }
}
