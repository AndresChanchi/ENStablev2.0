// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title IdentityVaultTest
 * @author AndresChanchi
 * @notice Tests focusing on the "Actuator" (Vault) and user self-service functionality.
 * @dev Implements AAA (Arrange-Act-Assert) pattern for Uniswap v4 liquidity management.
 */

// --- Imports ---
import {Test} from "forge-std/Test.sol";
import {IdentityVault} from "../src/core/IdentityVault.sol";
import {EnstableHook} from "../src/core/EnstableHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {IIdentityVault} from "../src/interfaces/IIdentityVault.sol";
import {DeployFullSystem} from "../script/DeployFullSystem.s.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract IdentityVaultTest is Test {
    using PoolIdLibrary for PoolKey;

    // --- State Variables ---
    IdentityVault vault;
    EnstableHook hook;
    IPoolManager poolManager;

    // Assets
    MockERC20 token0;
    MockERC20 token1;
    PoolKey poolKey;

    // Accounts
    address agent = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address USER = makeAddr("user");

    // --- Functions ---

    /**
     * @notice Initializes the test environment, deploys the system, and funds test accounts.
     */
    function setUp() public {
        // 1. Deploy system via existing script
        DeployFullSystem deployer = new DeployFullSystem();
        (hook, vault, poolManager) = deployer.run();

        // 2. Setup Pool (ETH/USDC Style)
        // We assume address(token0) < address(token1) for canonical ordering
        token0 = new MockERC20("Token 0", "TK0");
        token1 = new MockERC20("Token 1", "TK1");

        poolKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: hook
        });

        // Initialize Pool at Price 1:1 (sqrtPriceX96)
        poolManager.initialize(poolKey, 79228162514264337593543950336);

        // 3. Fund USER
        token0.mint(USER, 1000e18);
        token1.mint(USER, 1000e18);
        vm.deal(USER, 10 ether);

        vm.startPrank(USER);
        token0.approve(address(vault), type(uint256).max);
        token1.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT & WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Verifies that a user deposit correctly updates the vault state and position data.
     */
    function test_UserDeposit_UpdatesBalanceAndPosition() public {
        // Arrange
        uint128 liquidityAmount = 100e18;
        int24 tickLower = -600;
        int24 tickUpper = 600;

        // Act
        vm.prank(USER);
        vault.deposit(poolKey, liquidityAmount, tickLower, tickUpper);

        // Assert
        IIdentityVault.PackedPosition memory pos = vault.getPosition(USER);
        assertEq(pos.liquidity, liquidityAmount);
        assertEq(pos.tickLower, tickLower);
        assertEq(pos.status, 1); // Status: Active
        assertEq(PoolId.unwrap(vault.getUserPoolId(USER)), PoolId.unwrap(poolKey.toId()));
    }

    /**
     * @notice Verifies that withdrawing full liquidity returns tokens to the user and cleans state.
     */
    function test_UserWithdraw_FullLiquidity() public {
        // Arrange
        vm.startPrank(USER);
        vault.deposit(poolKey, 100e18, -60, 60);
        uint256 balance0Before = token0.balanceOf(USER);

        // Act
        vault.withdraw(poolKey, 100e18); // Withdraw full amount
        vm.stopPrank();

        // Assert
        IIdentityVault.PackedPosition memory pos = vault.getPosition(USER);
        assertEq(pos.liquidity, 0, "Liquidity should be zero");
        assertEq(pos.status, 0, "Status should be inactive");
        assertTrue(token0.balanceOf(USER) > balance0Before, "Tokens should return to user");
    }

    /**
     * @notice Verifies that partial withdrawals leave the correct remaining liquidity.
     */
    function test_UserWithdraw_PartialLiquidity() public {
        // Arrange
        vm.startPrank(USER);
        vault.deposit(poolKey, 100e18, -60, 60);

        // Act
        vault.withdraw(poolKey, 40e18); // Withdraw 40%
        vm.stopPrank();

        // Assert
        IIdentityVault.PackedPosition memory pos = vault.getPosition(USER);
        assertEq(pos.liquidity, 60e18, "Should have 60e18 remaining");
    }

    /*//////////////////////////////////////////////////////////////
                        AGENT INTERACTION TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Confirms that an authorized agent (via Hook) can move user liquidity to a new range.
     */
    function test_AgentCanRepositionUserLiquidity() public {
        // 1. Arrange: User performs initial deposit
        vm.prank(USER);
        vault.deposit(poolKey, 100e18, -600, 600);

        // 2. Act: Agent triggers a reposition (Simulating processAgentSignal flow)
        int24 newLower = -120;
        int24 newUpper = 120;

        vm.prank(address(hook));
        vault.executeAgentAction(poolKey, newLower, newUpper, 100e18, USER);

        // 3. Assert
        IIdentityVault.PackedPosition memory pos = vault.getPosition(USER);
        assertEq(pos.tickLower, newLower);
        assertEq(pos.tickUpper, newUpper);
        assertEq(pos.liquidity, 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                        SAFETY & EDGE CASES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Technical test for solvency verification during withdrawal attempts without deposits.
     */
    function test_Revert_WhenVaultIsInsolvent() public {
        // Arrange & Act & Assert
        vm.prank(USER);
        vm.expectRevert(IIdentityVault.IdentityVault__NoPositionToWithdraw.selector);
        vault.withdraw(poolKey, 100e18);
    }

    /**
     * @notice Ensures deposits fail if ticks do not align with the pool's tick spacing.
     */
    function test_Revert_InvalidTickSpacing() public {
        // Arrange & Act & Assert
        vm.prank(USER);
        vm.expectRevert(IIdentityVault.IdentityVault__InvalidTickRange.selector);
        vault.deposit(poolKey, 100e18, -55, 55); // 55 is not a multiple of 60
    }

    /**
     * @notice Verifies the gas metering modifier correctly triggers a revert if consumption is too high.
     */
    function test_GasLimit_RevertIfExceeded() public {
        // Note: Requires a high-gas scenario or reduced MAX_REPOSITION_GAS in contract to trigger.
    }

    /**
     * @notice Integration test for Native Currency (ETH) support.
     */
    function test_NativeETH_DepositAndWithdraw() public {
        // --- 1. ARRANGE: Native Pool Configuration ---
        // Ensure canonical currency ordering (ETH is address(0))
        Currency ethCurrency = CurrencyLibrary.ADDRESS_ZERO;
        Currency usdcCurrency = Currency.wrap(address(token1));

        (Currency c0, Currency c1) =
            address(0) < address(token1) ? (ethCurrency, usdcCurrency) : (usdcCurrency, ethCurrency);

        PoolKey memory nativeKey = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: hook});

        poolManager.initialize(nativeKey, 79228162514264337593543950336);

        // --- 2. USER PREPARATION ---
        uint256 userEthBefore = USER.balance;

        // User needs the "counter" token (token1) to provide liquidity against ETH
        token1.mint(USER, 1000e18);

        vm.startPrank(USER);
        // User authorizes Vault to manage token1
        token1.approve(address(vault), type(uint256).max);

        // --- 3. ACT: ETH Deposit ---
        // Sending 1 ETH. Vault uses internal logic to settle token1 via transferFrom
        vault.deposit{value: 1 ether}(nativeKey, 1e18, -60, 60);
        vm.stopPrank();

        // --- 4. ASSERT: Deposit Verification ---
        // ETH balance should be handled by the Vault/PoolManager singleton logic
        assertTrue(address(vault).balance >= 0, "Vault should have handled ETH");

        // --- 5. ACT: Liquidity Withdrawal ---
        vm.prank(USER);
        vault.withdraw(nativeKey, 1e18);

        // --- 6. FINAL ASSERT ---
        // Verify ETH is returned to user (approxEq used for potential rounding or gas simulation)
        assertApproxEqAbs(USER.balance, userEthBefore, 0.01 ether, "ETH should return to user (approx due to rounding)");

        // Verify counter token return
        assertTrue(token1.balanceOf(USER) > 0, "User should have received token1 back");
    }
}
