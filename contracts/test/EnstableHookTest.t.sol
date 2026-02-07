// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title EnstableHookTest
 * @author Andres Chanchi
 * @notice Integration tests for EnstableHook and IdentityVault on Unichain Sepolia Fork.
 * @dev Inherits from Forge Standard Test to provide testing utilities and cheatcodes.
 */

// --- Imports ---
import {Test} from "forge-std/Test.sol";
import {EnstableHook} from "../src/core/EnstableHook.sol";
import {IdentityVault} from "../src/core/IdentityVault.sol";
import {DeployFullSystem} from "../script/DeployFullSystem.s.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IEnstableHook} from "../src/interfaces/IEnstableHook.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

contract EnstableHookTest is Test {
    // --- Libraries ---
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    // --- State Variables ---
    EnstableHook hook;
    IdentityVault vault;
    IPoolManager poolManager;

    address agent = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address user = makeAddr("user");
    bytes32 mockEnsNode = keccak256("user.eth");

    PoolKey mockKey;
    MockERC20 token0;
    MockERC20 token1;

    // --- Functions ---

    /**
     * @notice Sets up the testing environment before each test case.
     * @dev Deploys the system, initializes mock tokens, and prepares the Uniswap V4 Pool.
     */
    function setUp() public {
        address deployerAddr = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        vm.deal(deployerAddr, 100 ether);

        DeployFullSystem deployer = new DeployFullSystem();
        (hook, vault, poolManager) = deployer.run();

        MockERC20 tokenA = new MockERC20("Token A", "TKA");
        MockERC20 tokenB = new MockERC20("Token B", "TKB");

        // Sort tokens to comply with Uniswap V4 expectations
        (address t0, address t1) =
            address(tokenA) < address(tokenB) ? (address(tokenA), address(tokenB)) : (address(tokenB), address(tokenA));

        token0 = MockERC20(t0);
        token1 = MockERC20(t1);

        mockKey = PoolKey({
            currency0: Currency.wrap(t0),
            currency1: Currency.wrap(t1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        // sqrtPriceX96 for price 1:1
        uint160 startingPrice = 79228162514264337593543950336;
        poolManager.initialize(mockKey, startingPrice);

        token0.mint(address(vault), 10000e18);
        token1.mint(address(vault), 10000e18);

        // Initial approvals for the default mockKey
        vm.startPrank(address(vault));
        token0.approve(address(poolManager), type(uint256).max);
        token1.approve(address(poolManager), type(uint256).max);
        vm.stopPrank();
    }

    /**
     * @notice Validates that an authorized agent can process a valid signal.
     * @dev Follows AAA pattern: Arrange (setup in setUp), Act (process signal), Assert.
     */
    function testProcessValidSignal_HappyPath() public {
        IEnstableHook.AgentSignal memory signal = _createSignal(40, -120, 120);

        vm.prank(agent);
        bytes32 poolId = PoolId.unwrap(mockKey.toId());

        vm.expectEmit(true, true, true, true);
        emit IEnstableHook.AgentSignalProcessed(user, poolId, -120, 120);

        hook.processAgentSignal(mockKey, user, signal);

        assertEq(hook.s_lastRiskUpdate(), block.timestamp);
        assertEq(hook.s_emergencyMode(), false);
    }

    /**
     * @notice Checks if the vault correctly deploys liquidity into the pool after a signal.
     */
    function testLiquidityProvisionOnSignal() public {
        int24 tickLower = -600;
        int24 tickUpper = 600;

        IEnstableHook.AgentSignal memory signal = _createSignal(20, tickLower, tickUpper);
        uint256 vaultBalance0Before = token0.balanceOf(address(vault));

        vm.prank(agent);
        hook.processAgentSignal(mockKey, user, signal);

        assertTrue(token0.balanceOf(address(vault)) < vaultBalance0Before, "Vault tokens should be deployed");

        // Compute position ID to verify liquidity in PoolManager
        bytes32 positionId = keccak256(abi.encodePacked(address(vault), tickLower, tickUpper, address(hook)));
        uint128 liquidity = poolManager.getPositionLiquidity(mockKey.toId(), positionId);

        if (liquidity == 0) {
            positionId = keccak256(abi.encodePacked(address(vault), tickLower, tickUpper, bytes32(0)));
            liquidity = poolManager.getPositionLiquidity(mockKey.toId(), positionId);
        }

        assertTrue(liquidity > 0, "Pool position should have active liquidity");
    }

    /**
     * @notice Verifies the circuit breaker functionality blocks swaps during high risk.
     */
    function testSwapFailsDuringEmergency() public {
        _activateEmergency();

        vm.prank(address(poolManager));
        vm.expectRevert(IEnstableHook.EnstableHook__CircuitBreakerActive.selector);

        hook.beforeSwap(address(0), mockKey, IPoolManager.SwapParams(true, 1e18, 0), "");
    }

    /**
     * @notice Ensures that signals older than the allowed threshold are rejected.
     */
    function testCannotProcessExpiredSignal() public {
        IEnstableHook.AgentSignal memory staleSignal = IEnstableHook.AgentSignal({
            currentPrice: 1e18,
            volatility: 0,
            recommendedLower: -120,
            recommendedUpper: 120,
            riskLevel: 0,
            ensNode: mockEnsNode,
            timestamp: block.timestamp - 11 minutes
        });

        vm.prank(agent);
        vm.expectRevert(IEnstableHook.EnstableHook__StaleSignal.selector);
        hook.processAgentSignal(mockKey, user, staleSignal);
    }

    /**
     * @notice Verifies that a valid low-risk signal can deactivate the emergency mode.
     */
    function testEmergencyRecovery() public {
        _activateEmergency();
        assertTrue(hook.s_emergencyMode());

        IEnstableHook.AgentSignal memory recoverySignal = _createSignal(10, -120, 120);

        vm.prank(agent);
        hook.processAgentSignal(mockKey, user, recoverySignal);

        assertFalse(hook.s_emergencyMode(), "Should recover from emergency mode");
    }

    /**
     * @notice Ensures only authorized agent addresses can trigger signal processing.
     */
    function testOnlyAgentCanSignal() public {
        IEnstableHook.AgentSignal memory signal = _createSignal(40, -120, 120);
        vm.prank(user);
        vm.expectRevert(IEnstableHook.EnstableHook__NotAuthorizedAgent.selector);
        hook.processAgentSignal(mockKey, user, signal);
    }

    /**
     * @notice Tests Native ETH support within the hook and vault.
     */
    function test_NativeCurrencySupport() public {
        MockERC20 tokenUsdc = new MockERC20("USDC", "USDC");
        Currency ethCurrency = CurrencyLibrary.ADDRESS_ZERO;
        Currency usdcCurrency = Currency.wrap(address(tokenUsdc));

        (Currency c0, Currency c1) =
            address(0) < address(tokenUsdc) ? (ethCurrency, usdcCurrency) : (usdcCurrency, ethCurrency);

        PoolKey memory nativeKey =
            PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(hook))});

        poolManager.initialize(nativeKey, 79228162514264337593543950336);

        // Vault Configuration
        vault.allowToken(address(tokenUsdc));
        vm.deal(address(vault), 1000 ether);
        tokenUsdc.mint(address(vault), 1000 ether);

        IEnstableHook.AgentSignal memory signal = _createSignal(20, -600, 600);
        signal.volatility = 1e18;

        vm.prank(agent);
        hook.processAgentSignal(nativeKey, user, signal);

        // Verification of Liquidity in Native Pool
        bytes32 posIdWithHook = keccak256(abi.encodePacked(address(vault), int24(-600), int24(600), address(hook)));
        bytes32 posIdNoHook = keccak256(abi.encodePacked(address(vault), int24(-600), int24(600), bytes32(0)));

        uint128 liqWith = poolManager.getPositionLiquidity(nativeKey.toId(), posIdWithHook);
        uint128 liqNo = poolManager.getPositionLiquidity(nativeKey.toId(), posIdNoHook);

        assertTrue(liqWith > 0 || liqNo > 0, "Should provide liquidity with Native ETH");
    }

    /**
     * @notice Placeholder for future slippage protection testing.
     */
    function test_SlippageProtection_HardLimit() public pure {
        // Future implementation
    }

    /**
     * @notice Ensures that sending the exact same signal twice skips intensive logic to save gas.
     */
    function test_IgnoreDuplicateSignal() public {
        IEnstableHook.AgentSignal memory signal = _createSignal(20, -120, 120);

        vm.startPrank(agent);
        hook.processAgentSignal(mockKey, user, signal);

        uint256 gasBefore = gasleft();
        hook.processAgentSignal(mockKey, user, signal);
        uint256 gasUsed = gasBefore - gasleft();

        assertTrue(gasUsed < 10000, "Should skip redundant execution");
        vm.stopPrank();
    }

    // --- Internal Helpers ---

    /**
     * @dev Creates a mock AgentSignal struct.
     * @param risk The risk level to set.
     * @param lower The lower tick boundary.
     * @param upper The upper tick boundary.
     * @return A populated AgentSignal memory struct.
     */
    function _createSignal(uint128 risk, int24 lower, int24 upper)
        internal
        view
        returns (IEnstableHook.AgentSignal memory)
    {
        return IEnstableHook.AgentSignal({
            currentPrice: 1e18,
            volatility: 10,
            recommendedLower: lower,
            recommendedUpper: upper,
            riskLevel: risk,
            ensNode: mockEnsNode,
            timestamp: block.timestamp
        });
    }

    /**
     * @dev Helper to force the contract into emergency mode by simulating extreme volatility.
     */
    function _activateEmergency() internal {
        IEnstableHook.AgentSignal memory extremeSignal = IEnstableHook.AgentSignal({
            currentPrice: 1e18,
            volatility: 1000,
            recommendedLower: 0,
            recommendedUpper: 0,
            riskLevel: 100,
            ensNode: mockEnsNode,
            timestamp: block.timestamp
        });
        vm.prank(agent);
        hook.processAgentSignal(mockKey, user, extremeSignal);
    }
}
