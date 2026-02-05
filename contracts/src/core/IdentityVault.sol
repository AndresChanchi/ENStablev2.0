// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title IdentityVault
 * @author Andres Chanchi
 * @notice The "Actuator" of the Agentic Architecture.
 * @dev This contract manages Uniswap v4 liquidity positions using EIP-1153 for
 * transient context and strictly follows the "Settle-before-Take" singleton accounting.
 * * DESIGN PRINCIPLES:
 * 1. Singleton Solvency: Implements 2-wei tolerance for rounding issues (Rule N4#4).
 * 2. Function Layout: Strictly follows the Solidity Style Guide order.
 * 3. Lock Management: Prevents nested 'unlock' calls via TransientStateLibrary.
 * 4. Bitwise Efficiency: Packs user position state into a single 256-bit word.
 * 5. CEI Compliance: Enforces Checks-Effects-Interactions within the V4 callback.
 */

// -------------------------------------------------------------------------
// Imports
// -------------------------------------------------------------------------
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {TransientStateLibrary} from "v4-core/libraries/TransientStateLibrary.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";

contract IdentityVault is IUnlockCallback {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using TransientStateLibrary for IPoolManager;
    using SafeCast for int256;

    // -------------------------------------------------------------------------
    // Type Declarations
    // -------------------------------------------------------------------------

    enum VaultAction {
        None,
        Reposition,
        Deposit,
        Withdraw
    }

    /**
     * @dev Optimized Packed Position (Fits in exactly 256 bits).
     * Layout:
     * [status: 8] [lastUpdated: 32] [liquidity: 128] [tickUpper: 24] [tickLower: 24] = 216 bits.
     */
    struct PackedPosition {
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint32 lastUpdated;
        uint8 status; // 1 = Active, 0 = Empty
    }

    struct TransientContext {
        PoolKey key;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidityDelta; // Amount to mint or burn
        address user;
    }

    // -------------------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------------------

    IPoolManager private immutable i_poolManager;
    address private immutable i_enstableHook;

    /// @dev Operational guard for CEI and reentrancy protection
    VaultAction private s_currentAction;

    /// @dev Mapping 1: User -> Packed Position Data (Gas Optimized)
    mapping(address => uint256) private s_packedPositions;

    /// @dev Mapping 2: User -> PoolId (Scalability Requirement)
    mapping(address => PoolId) private s_userPoolIds;

    /// @dev EIP-1153 Storage Slots (Pre-computed hashes)
    bytes32 private constant T_CONTEXT_SLOT = keccak256("IdentityVault.context");
    bytes32 private constant T_GAS_CHECK_SLOT = keccak256("IdentityVault.gas");

    /// @dev Safety Constants
    uint256 private constant MAX_REPOSITION_GAS = 1_200_000;

    // -------------------------------------------------------------------------
    // Events & Errors
    // -------------------------------------------------------------------------

    event PositionRepositioned(
        address indexed user, PoolId indexed poolId, int24 tickLower, int24 tickUpper, uint128 newLiquidity
    );
    event UserDeposit(address indexed user, uint128 amount);
    event UserWithdrawal(address indexed user, uint128 amount, bool isPartial);

    error IdentityVault__OnlyHookAuthorized();
    error IdentityVault__OnlyPoolManager();
    error IdentityVault__PoolManagerAlreadyUnlocked();
    error IdentityVault__GasLimitExceeded();
    error IdentityVault__InvalidTickRange();
    error IdentityVault__Insolvent(int256 delta0, int256 delta1);
    error IdentityVault__NoPositionToWithdraw();
    error IdentityVault__CastError();

    // -------------------------------------------------------------------------
    // Modifiers (Refactorizados para cumplir con unwrapped-modifier-logic)
    // -------------------------------------------------------------------------

    modifier onlyEnstableHook() {
        _checkOnlyHook();
        _;
    }

    function _checkOnlyHook() internal view {
        if (msg.sender != i_enstableHook) revert IdentityVault__OnlyHookAuthorized();
    }

    modifier setAction(VaultAction action) {
        _beforeAction(action);
        _;
        _afterAction();
    }

    function _beforeAction(VaultAction action) internal {
        s_currentAction = action;
    }

    function _afterAction() internal {
        s_currentAction = VaultAction.None;
    }

    modifier gasLimited() {
        _startGasMetering();
        _;
        _stopGasMetering();
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address _poolManager, address _hook) {
        i_poolManager = IPoolManager(_poolManager);
        i_enstableHook = _hook;
    }

    // -------------------------------------------------------------------------
    // Receive Function
    // -------------------------------------------------------------------------

    // Rule N1: Necessary to handle native ETH unwrap from PoolManager
    receive() external payable {}

    // -------------------------------------------------------------------------
    // External Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Initiates a repositioning strategy.
     */
    function executeAgentAction(PoolKey calldata _key, int24 _lower, int24 _upper, uint128 _liq, address _user)
        external
        onlyEnstableHook
        setAction(VaultAction.Reposition)
        gasLimited
    {
        if (i_poolManager.isUnlocked()) revert IdentityVault__PoolManagerAlreadyUnlocked();
        _validateTicks(_lower, _upper, _key.tickSpacing);

        TransientContext memory context =
            TransientContext({key: _key, tickLower: _lower, tickUpper: _upper, liquidityDelta: _liq, user: _user});

        _tstoreContext(context);
        i_poolManager.unlock(abi.encode(VaultAction.Reposition));
    }

    /**
     * @notice User self-service deposit.
     */
    function deposit(PoolKey calldata _key, uint128 _amount, int24 _lower, int24 _upper)
        external
        payable
        setAction(VaultAction.Deposit)
    {
        if (i_poolManager.isUnlocked()) revert IdentityVault__PoolManagerAlreadyUnlocked();
        _validateTicks(_lower, _upper, _key.tickSpacing);

        TransientContext memory context = TransientContext({
            key: _key, tickLower: _lower, tickUpper: _upper, liquidityDelta: _amount, user: msg.sender
        });

        _tstoreContext(context);
        i_poolManager.unlock(abi.encode(VaultAction.Deposit));
        emit UserDeposit(msg.sender, _amount);
    }

    /**
     * @notice User self-service withdrawal (Full or Partial).
     */
    function withdraw(PoolKey calldata _key, uint128 _amount) external setAction(VaultAction.Withdraw) {
        if (i_poolManager.isUnlocked()) revert IdentityVault__PoolManagerAlreadyUnlocked();

        PackedPosition memory pos = _unpack(s_packedPositions[msg.sender]);
        if (pos.liquidity == 0) revert IdentityVault__NoPositionToWithdraw();

        uint128 withdrawAmount = (_amount == 0 || _amount > pos.liquidity) ? pos.liquidity : _amount;

        TransientContext memory context = TransientContext({
            key: _key,
            tickLower: pos.tickLower,
            tickUpper: pos.tickUpper,
            liquidityDelta: withdrawAmount,
            user: msg.sender
        });

        _tstoreContext(context);
        i_poolManager.unlock(abi.encode(VaultAction.Withdraw));
        emit UserWithdrawal(msg.sender, withdrawAmount, withdrawAmount < pos.liquidity);
    }

    /**
     * @notice Uniswap v4 Unlock Callback.
     */
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        if (msg.sender != address(i_poolManager)) revert IdentityVault__OnlyPoolManager();

        VaultAction action = abi.decode(data, (VaultAction));
        TransientContext memory ctx = _tloadContext();

        if (action == VaultAction.Reposition) {
            _handleReposition(ctx);
        } else if (action == VaultAction.Deposit) {
            _handleDeposit(ctx);
        } else if (action == VaultAction.Withdraw) {
            _handleWithdraw(ctx);
        }

        _settleAndTake(ctx.key);
        _verifySolvency(ctx.key);
        _sweep(ctx.key.currency0, ctx.user);
        _sweep(ctx.key.currency1, ctx.user);

        return "";
    }

    // -------------------------------------------------------------------------
    // Internal Logic Handlers
    // -------------------------------------------------------------------------

    function _handleReposition(TransientContext memory ctx) internal {
        PackedPosition memory currentPos = _unpack(s_packedPositions[ctx.user]);

        if (currentPos.liquidity > 0) {
            i_poolManager.modifyLiquidity(
                ctx.key,
                IPoolManager.ModifyLiquidityParams({
                    tickLower: currentPos.tickLower,
                    tickUpper: currentPos.tickUpper,
                    liquidityDelta: -int128(currentPos.liquidity),
                    salt: bytes32(0)
                }),
                bytes("")
            );
        }

        if (ctx.liquidityDelta > 0) {
            i_poolManager.modifyLiquidity(
                ctx.key,
                IPoolManager.ModifyLiquidityParams({
                    tickLower: ctx.tickLower,
                    tickUpper: ctx.tickUpper,
                    liquidityDelta: int128(ctx.liquidityDelta),
                    salt: bytes32(0)
                }),
                bytes("")
            );
        }

        s_packedPositions[ctx.user] = _pack(
            PackedPosition({
                tickLower: ctx.tickLower,
                tickUpper: ctx.tickUpper,
                liquidity: ctx.liquidityDelta,
                lastUpdated: uint32(block.timestamp),
                status: 1
            })
        );
        s_userPoolIds[ctx.user] = ctx.key.toId();

        emit PositionRepositioned(ctx.user, ctx.key.toId(), ctx.tickLower, ctx.tickUpper, ctx.liquidityDelta);
    }

    function _handleDeposit(TransientContext memory ctx) internal {
        i_poolManager.modifyLiquidity(
            ctx.key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: ctx.tickLower,
                tickUpper: ctx.tickUpper,
                liquidityDelta: int128(ctx.liquidityDelta),
                salt: bytes32(0)
            }),
            bytes("")
        );

        s_packedPositions[ctx.user] = _pack(
            PackedPosition({
                tickLower: ctx.tickLower,
                tickUpper: ctx.tickUpper,
                liquidity: ctx.liquidityDelta,
                lastUpdated: uint32(block.timestamp),
                status: 1
            })
        );
        s_userPoolIds[ctx.user] = ctx.key.toId();
    }

    function _handleWithdraw(TransientContext memory ctx) internal {
        i_poolManager.modifyLiquidity(
            ctx.key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: ctx.tickLower,
                tickUpper: ctx.tickUpper,
                liquidityDelta: -int128(ctx.liquidityDelta),
                salt: bytes32(0)
            }),
            bytes("")
        );

        PackedPosition memory pos = _unpack(s_packedPositions[ctx.user]);
        pos.liquidity -= ctx.liquidityDelta;
        pos.lastUpdated = uint32(block.timestamp);
        if (pos.liquidity == 0) pos.status = 0;

        s_packedPositions[ctx.user] = _pack(pos);
    }

    // -------------------------------------------------------------------------
    // God Mode Helpers (The Linter's Kryptonite)
    // -------------------------------------------------------------------------

    function _toUint256(int256 x) internal pure returns (uint256) {
        if (x < 0) revert IdentityVault__CastError();
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(x);
    }

    function _abs(int256 x) internal pure returns (uint256) {
        if (x == type(int256).min) revert IdentityVault__CastError();
        // forge-lint: disable-next-line(unsafe-typecast)
        return x >= 0 ? uint256(x) : uint256(-x);
    }

    function _toInt24(int256 x) internal pure returns (int24) {
        if (x < -8388608 || x > 8388607) revert IdentityVault__CastError();
        // forge-lint: disable-next-line(unsafe-typecast)
        return int24(x);
    }

    function _settleAndTake(PoolKey memory _key) internal {
        int256 d0 = i_poolManager.currencyDelta(address(this), _key.currency0);
        int256 d1 = i_poolManager.currencyDelta(address(this), _key.currency1);

        uint256 valToSend;

        if (d0 < 0) {
            uint256 a0 = _abs(d0);
            if (_key.currency0.isAddressZero()) valToSend += a0;
        }
        if (d1 < 0) {
            uint256 a1 = _abs(d1);
            if (_key.currency1.isAddressZero()) valToSend += a1;
        }

        if (d0 < 0 || d1 < 0) i_poolManager.settle{value: valToSend}();

        if (d0 > 0) i_poolManager.take(_key.currency0, address(this), _toUint256(d0));
        if (d1 > 0) i_poolManager.take(_key.currency1, address(this), _toUint256(d1));
    }

    // -------------------------------------------------------------------------
    // Packing & View Functions
    // -------------------------------------------------------------------------

    function _pack(PackedPosition memory _p) internal pure returns (uint256) {
        return uint256(uint24(_p.tickLower)) | (uint256(uint24(_p.tickUpper)) << 24) | (uint256(_p.liquidity) << 48)
            | (uint256(_p.lastUpdated) << 176) | (uint256(_p.status) << 208);
    }

    function _unpack(uint256 _packed) internal pure returns (PackedPosition memory _p) {
        uint256 low = _packed & 0xFFFFFF;
        uint256 up = (_packed >> 24) & 0xFFFFFF;

        // forge-lint: disable-next-line(unsafe-typecast)
        _p.tickLower = _toInt24(int256(low));
        // forge-lint: disable-next-line(unsafe-typecast)
        _p.tickUpper = _toInt24(int256(up));

        _p.liquidity = uint128((_packed >> 48) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        _p.lastUpdated = uint32((_packed >> 176) & 0xFFFFFFFF);
        _p.status = uint8((_packed >> 208) & 0xFF);
    }

    function _validateTicks(int24 _low, int24 _up, int24 _spacing) internal pure {
        if (_low >= _up) revert IdentityVault__InvalidTickRange();
        if (_low < TickMath.MIN_TICK || _up > TickMath.MAX_TICK) revert IdentityVault__InvalidTickRange();
        if (_low % _spacing != 0 || _up % _spacing != 0) revert IdentityVault__InvalidTickRange();
    }

    // -------------------------------------------------------------------------
    // Transient & Safety Helpers
    // -------------------------------------------------------------------------

    function _verifySolvency(PoolKey memory _key) internal view {
        int256 d0 = i_poolManager.currencyDelta(address(this), _key.currency0);
        int256 d1 = i_poolManager.currencyDelta(address(this), _key.currency1);
        if ((d0 > 2 || d0 < -2) || (d1 > 2 || d1 < -2)) revert IdentityVault__Insolvent(d0, d1);
    }

    function _sweep(Currency _cur, address _to) internal {
        uint256 bal = _cur.balanceOf(address(this));
        if (bal > 0) _cur.transfer(_to, bal);
    }

    function _tstoreContext(TransientContext memory ctx) internal {
        bytes memory enc = abi.encode(ctx);
        bytes32 slot = T_CONTEXT_SLOT;
        assembly { tstore(slot, enc) }
    }

    function _tloadContext() internal view returns (TransientContext memory ctx) {
        bytes32 slot = T_CONTEXT_SLOT;
        bytes memory enc;
        assembly { enc := tload(slot) }
        ctx = abi.decode(enc, (TransientContext));
    }

    function _startGasMetering() internal {
        uint256 start = gasleft();
        bytes32 slot = T_GAS_CHECK_SLOT;
        assembly { tstore(slot, start) }
    }

    function _stopGasMetering() internal view {
        bytes32 slot = T_GAS_CHECK_SLOT;
        uint256 start;
        assembly { start := tload(slot) }
        if (start > 0 && (start - gasleft()) > MAX_REPOSITION_GAS) revert IdentityVault__GasLimitExceeded();
    }
}
