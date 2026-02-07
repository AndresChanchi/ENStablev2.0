// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title EnstableHook
 * @author Andres Chanchi & ENStable Team (EthGlobal 2026)
 * @notice The "Brain" of the Agentic Architecture.
 * @dev This contract acts as the primary controller for Uniswap v4 pools,
 * processing AI-driven signals to manage risk and trigger vault actions.
 */

// Imports
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {IIdentityVault} from "../interfaces/IIdentityVault.sol";
import {IEnstableHook} from "../interfaces/IEnstableHook.sol";

// Interfaces, Libraries, Contracts
contract EnstableHook is IHooks, IEnstableHook {
    using PoolIdLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;
    using CurrencyLibrary for Currency;

    // Type Declarations - Inherited from IEnstableHook

    // State Variables
    IPoolManager public immutable i_poolManager;
    IIdentityVault public immutable i_vault;
    address public immutable i_agentAccount;

    bool public s_emergencyMode;
    uint256 public s_lastRiskUpdate;

    uint256 public constant MAX_SIGNAL_AGE = 5 minutes;
    uint128 public constant MAX_RISK_THRESHOLD = 90;

    // Events - Inherited from IEnstableHook

    // Modifiers
    modifier onlyAgent() {
        _checkOnlyAgent();
        _;
    }

    modifier onlyPoolManager() {
        _checkOnlyPoolManager();
        _;
    }

    // Functions

    // Constructor
    constructor(IPoolManager _poolManager, address _vault, address _agentAccount) {
        i_poolManager = _poolManager;
        i_vault = IIdentityVault(_vault);
        i_agentAccount = _agentAccount;
    }

    // External Functions
    /**
     * @notice Processes market signals sent by the authorized AI Agent.
     * @dev Triggers the Circuit Breaker if risk levels are critical.
     * @param _key The PoolKey identifying the Uniswap V4 pool.
     * @param _user The owner of the liquidity position.
     * @param _signal Market data and recommended ranges from the agent.
     */
    function processAgentSignal(PoolKey calldata _key, address _user, AgentSignal calldata _signal)
        external
        override
        onlyAgent
    {
        if (!_isSignalValid(_signal)) {
            emit RiskLevelExceeded(_user, _signal.riskLevel);
            if (_signal.riskLevel == 100) {
                s_emergencyMode = true;
                emit CircuitBreakerActivated("Extreme Risk Detected by AI");
            }
            revert EnstableHook__ExtremeVolatility();
        }

        if (s_emergencyMode && _signal.riskLevel < 50) {
            s_emergencyMode = false;
        }

        s_lastRiskUpdate = block.timestamp;

        emit AgentSignalProcessed(_user, PoolId.unwrap(_key.toId()), _signal.recommendedLower, _signal.recommendedUpper);

        i_vault.executeAgentAction(
            _key, _signal.recommendedLower, _signal.recommendedUpper, uint128(_signal.volatility), _user
        );
    }

    /**
     * @notice Hook called by PoolManager before adding liquidity.
     * @dev Validates that the sender is the authorized vault and checks ENS credentials.
     */
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata hookData
    ) external view override onlyPoolManager returns (bytes4) {
        if (sender != address(i_vault)) revert EnstableHook__NotAuthorizedVault();
        if (hookData.length == 0) revert EnstableHook__InvalidHookData();

        address user = abi.decode(hookData, (address));
        if (!_mockValidateEns(user)) revert EnstableHook__InvalidENSNode();

        return IHooks.beforeAddLiquidity.selector;
    }

    /**
     * @notice Hook called by PoolManager before removing liquidity.
     */
    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata hookData
    ) external view override onlyPoolManager returns (bytes4) {
        if (sender != address(i_vault)) revert EnstableHook__NotAuthorizedVault();
        if (hookData.length > 0) {
            address user = abi.decode(hookData, (address));
            if (user == address(0)) revert EnstableHook__InvalidHookData();
        }
        return IHooks.beforeRemoveLiquidity.selector;
    }

    /**
     * @notice Hook called by PoolManager before a swap.
     * @dev Acts as a circuit breaker; if emergency mode is active, swaps are blocked.
     */
    function beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata)
        external
        view
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (s_emergencyMode) {
            revert EnstableHook__CircuitBreakerActive();
        }
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    // Public Functions
    /**
     * @notice Defines the permissions for this hook.
     */
    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            beforeRemoveLiquidity: true,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // Internal Functions
    function _checkOnlyAgent() internal view {
        if (msg.sender != i_agentAccount) revert EnstableHook__NotAuthorizedAgent();
    }

    function _checkOnlyPoolManager() internal view {
        if (msg.sender != address(i_poolManager)) revert EnstableHook__OnlyPoolManager();
    }

    function _isSignalValid(AgentSignal calldata _signal) internal view returns (bool) {
        if (block.timestamp > _signal.timestamp + MAX_SIGNAL_AGE) return false;
        if (_signal.riskLevel > MAX_RISK_THRESHOLD) return false;
        return true;
    }

    // Internal & Private View & Pure Functions
    /**
     * @dev Mock implementation for ENS node validation.
     */
    function _mockValidateEns(
        address /*user*/
    )
        internal
        pure
        returns (bool)
    {
        return true;
    }

    // External & Public View & Pure Functions
    /**
     * @notice Returns the address of the authorized AI Agent.
     */
    function getAgentAccount() external view override returns (address) {
        return i_agentAccount;
    }

    /**
     * @dev Stub for beforeInitialize to comply with IHooks interface.
     */
    function beforeInitialize(address, PoolKey calldata, uint160) external pure override returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }

    /**
     * @dev Stub for afterInitialize to comply with IHooks interface.
     */
    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure override returns (bytes4) {
        return IHooks.afterInitialize.selector;
    }

    /**
     * @dev Stub for afterAddLiquidity to comply with IHooks interface.
     */
    function afterAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        return (IHooks.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    /**
     * @dev Stub for afterRemoveLiquidity to comply with IHooks interface.
     */
    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        return (IHooks.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    /**
     * @dev Stub for afterSwap to comply with IHooks interface.
     */
    function afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        pure
        override
        returns (bytes4, int128)
    {
        return (IHooks.afterSwap.selector, 0);
    }

    /**
     * @dev Stub for beforeDonate to comply with IHooks interface.
     */
    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IHooks.beforeDonate.selector;
    }

    /**
     * @dev Stub for afterDonate to comply with IHooks interface.
     */
    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IHooks.afterDonate.selector;
    }
}
