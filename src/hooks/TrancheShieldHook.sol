// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/utils/BaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

import {ITrancheShieldHook} from "../interfaces/ITrancheShieldHook.sol";
import {IProtectionReserve} from "../interfaces/IProtectionReserve.sol";

/// @title TrancheShieldHook
/// @notice Uniswap v4 hook implementing the TrancheShield risk-tranched LP system.
///         Phase 2 scope: tranche tracking and deposit/withdraw bookkeeping. Dynamic
///         fee, premium routing, IL math, and loss-waterfall payout are wired in Phase 3.
/// @dev    Hook permission bits used (six):
///         beforeAddLiquidity, afterAddLiquidity, beforeRemoveLiquidity, afterRemoveLiquidity,
///         beforeSwap, afterSwap. Mining must target these exact 6 flags.
contract TrancheShieldHook is BaseHook, ITrancheShieldHook {
    using StateLibrary for IPoolManager;

    // ---------------------------------------------------------------------
    // Constants — risk-state defaults applied on pool first-touch
    // ---------------------------------------------------------------------

    uint256 private constant DEFAULT_FEE_MULTIPLIER_BPS = 10_000; // 1.00x (LOW mode)
    uint256 private constant DEFAULT_COVERAGE_RATIO_BPS = 5_000;  // 50% — protocol-wide ceiling

    /// @dev `hookData` for add-liquidity is `abi.encode(Tranche, address owner)` → 64 bytes.
    uint256 private constant ADD_LIQUIDITY_HOOK_DATA_LEN = 64;

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error InvalidHookData();
    error SeniorDepositsDisabled();
    error PositionNotFound();
    error PositionAlreadyClosed();
    error NotCallbackReceiver();
    error CallbackReceiverAlreadySet();
    error ZeroAddress();
    error LiquidityDeltaInvalid();

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    IProtectionReserve public immutable reserve;

    /// @notice Set once by the deployer after `CallbackReceiver` is created.
    address public callbackReceiver;

    mapping(PoolId => PoolRiskState) internal _poolRiskState;
    mapping(bytes32 => LPPosition) internal _positions;

    /// @dev True once the pool has been touched and its risk state is initialized.
    mapping(PoolId => bool) internal _poolInitialized;

    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------

    modifier onlyCallbackReceiver() {
        if (msg.sender != callbackReceiver) revert NotCallbackReceiver();
        _;
    }

    // ---------------------------------------------------------------------
    // Constructor / init
    // ---------------------------------------------------------------------

    constructor(IPoolManager _poolManager, IProtectionReserve _reserve) BaseHook(_poolManager) {
        if (address(_reserve) == address(0)) revert ZeroAddress();
        reserve = _reserve;
    }

    /// @notice One-time setter for the CallbackReceiver address. The receiver is deployed
    ///         after the hook (it depends on the hook address), so we wire it post-construction.
    function setCallbackReceiver(address _receiver) external {
        if (callbackReceiver != address(0)) revert CallbackReceiverAlreadySet();
        if (_receiver == address(0)) revert ZeroAddress();
        callbackReceiver = _receiver;
    }

    // ---------------------------------------------------------------------
    // Hook permissions
    // ---------------------------------------------------------------------

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: true,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ---------------------------------------------------------------------
    // Hook lifecycle — Phase 2: tranche tracking
    // ---------------------------------------------------------------------

    function _beforeAddLiquidity(
        address, /* sender */
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        if (params.liquidityDelta <= 0) revert LiquidityDeltaInvalid();
        if (hookData.length != ADD_LIQUIDITY_HOOK_DATA_LEN) revert InvalidHookData();

        (Tranche tranche, address owner) = abi.decode(hookData, (Tranche, address));
        if (owner == address(0)) revert ZeroAddress();

        PoolId poolId = key.toId();
        _ensurePoolInitialized(poolId);

        if (tranche == Tranche.SENIOR && !_poolRiskState[poolId].seniorDepositsEnabled) {
            revert SeniorDepositsDisabled();
        }

        return IHooks.beforeAddLiquidity.selector;
    }

    function _afterAddLiquidity(
        address, /* sender */
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta, /* feesAccrued */
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        // hookData length and tranche validity already enforced in _beforeAddLiquidity.
        (Tranche tranche, address owner) = abi.decode(hookData, (Tranche, address));

        PoolId poolId = key.toId();
        bytes32 posKey = _positionKey(poolId, owner, params.tickLower, params.tickUpper, params.salt);

        // Read pool's current sqrtPrice for entry-price snapshot (used in Phase 3 IL math).
        (uint160 sqrtPriceX96, int24 tick,,) = poolManager.getSlot0(poolId);

        // Convert the BalanceDelta into the absolute deposit amounts. v4 reports negative
        // deltas for tokens flowing from the LP into the pool.
        uint256 amount0 = _abs(BalanceDeltaLibrary.amount0(delta));
        uint256 amount1 = _abs(BalanceDeltaLibrary.amount1(delta));

        _positions[posKey] = LPPosition({
            owner: owner,
            tranche: tranche,
            liquidity: uint256(params.liquidityDelta),
            depositedAmount0: amount0,
            depositedAmount1: amount1,
            entryValueToken1: 0, // populated in Phase 3 (full-range valuation against entry price)
            entrySqrtPriceX96: sqrtPriceX96,
            entryTick: tick,
            entryTimestamp: block.timestamp,
            active: true
        });

        // Phase-2 placeholder: track exposure by raw liquidity. Phase 3 swaps this to a
        // token1-denominated `perPositionCoverageCap` derived from `entryValueToken1`.
        if (tranche == Tranche.SENIOR) {
            _poolRiskState[poolId].seniorLiability += uint256(params.liquidityDelta);
            reserve.increaseSeniorLiability(poolId, owner, uint256(params.liquidityDelta));
        } else {
            _poolRiskState[poolId].juniorCollateral += uint256(params.liquidityDelta);
            reserve.increaseJuniorCollateral(poolId, owner, uint256(params.liquidityDelta));
        }

        emit PositionOpened(posKey, owner, poolId, tranche, uint256(params.liquidityDelta), 0);

        return (IHooks.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function _beforeRemoveLiquidity(
        address, /* sender */
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        if (params.liquidityDelta >= 0) revert LiquidityDeltaInvalid();
        if (hookData.length != ADD_LIQUIDITY_HOOK_DATA_LEN) revert InvalidHookData();

        (, address owner) = abi.decode(hookData, (Tranche, address));
        PoolId poolId = key.toId();
        bytes32 posKey = _positionKey(poolId, owner, params.tickLower, params.tickUpper, params.salt);

        LPPosition storage position = _positions[posKey];
        if (!position.active) revert PositionNotFound();

        if (position.tranche == Tranche.SENIOR) {
            emit SeniorWithdrawalRequested(poolId, owner, uint256(-params.liquidityDelta), block.timestamp);
        }

        return IHooks.beforeRemoveLiquidity.selector;
    }

    function _afterRemoveLiquidity(
        address, /* sender */
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta, /* delta */
        BalanceDelta, /* feesAccrued */
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        (, address owner) = abi.decode(hookData, (Tranche, address));
        PoolId poolId = key.toId();
        bytes32 posKey = _positionKey(poolId, owner, params.tickLower, params.tickUpper, params.salt);

        LPPosition storage position = _positions[posKey];
        if (!position.active) revert PositionAlreadyClosed();

        // Phase 2 only supports full-position withdrawals (single-shot close). Partial
        // withdrawals get proper accounting in Phase 3 along with IL math.
        position.active = false;

        if (position.tranche == Tranche.SENIOR) {
            _poolRiskState[poolId].seniorLiability -= position.liquidity;
            reserve.decreaseSeniorLiability(poolId, owner, position.liquidity);
        } else {
            _poolRiskState[poolId].juniorCollateral -= position.liquidity;
            reserve.decreaseJuniorCollateral(poolId, owner, position.liquidity);
        }

        emit PositionClosed(posKey, owner, poolId, 0, 0);

        return (IHooks.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    // ---------------------------------------------------------------------
    // Swap hooks — Phase 3 will fill these in (dynamic fee + premium routing)
    // ---------------------------------------------------------------------

    function _beforeSwap(
        address, /* sender */
        PoolKey calldata, /* key */
        SwapParams calldata, /* params */
        bytes calldata /* hookData */
    ) internal pure override returns (bytes4, BeforeSwapDelta, uint24) {
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(
        address, /* sender */
        PoolKey calldata, /* key */
        SwapParams calldata, /* params */
        BalanceDelta, /* delta */
        bytes calldata /* hookData */
    ) internal pure override returns (bytes4, int128) {
        return (IHooks.afterSwap.selector, 0);
    }

    // ---------------------------------------------------------------------
    // Admin setters — invoked exclusively by the CallbackReceiver
    // ---------------------------------------------------------------------

    function setRiskMode(PoolId poolId, RiskMode newMode) external override onlyCallbackReceiver {
        _ensurePoolInitialized(poolId);
        PoolRiskState storage state = _poolRiskState[poolId];
        RiskMode oldMode = state.mode;
        state.mode = newMode;
        state.lastRiskUpdate = block.timestamp;
        emit RiskModeChanged(poolId, oldMode, newMode);
    }

    function updateFeeMultiplier(PoolId poolId, uint256 newBps) external override onlyCallbackReceiver {
        _ensurePoolInitialized(poolId);
        PoolRiskState storage state = _poolRiskState[poolId];
        uint256 oldBps = state.feeMultiplierBps;
        state.feeMultiplierBps = newBps;
        state.lastRiskUpdate = block.timestamp;
        emit FeeMultiplierUpdated(poolId, oldBps, newBps);
    }

    function updateCoverageRatio(PoolId poolId, uint256 newBps) external override onlyCallbackReceiver {
        _ensurePoolInitialized(poolId);
        PoolRiskState storage state = _poolRiskState[poolId];
        uint256 oldBps = state.coverageRatioBps;
        state.coverageRatioBps = newBps;
        state.lastRiskUpdate = block.timestamp;
        emit CoverageRatioUpdated(poolId, oldBps, newBps);
    }

    function setSeniorDepositStatus(PoolId poolId, bool enabled) external override onlyCallbackReceiver {
        _ensurePoolInitialized(poolId);
        PoolRiskState storage state = _poolRiskState[poolId];
        state.seniorDepositsEnabled = enabled;
        state.lastRiskUpdate = block.timestamp;
        emit SeniorDepositStatusChanged(poolId, enabled);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function getPoolRiskState(PoolId poolId) external view override returns (PoolRiskState memory) {
        return _poolRiskState[poolId];
    }

    function getPosition(bytes32 key) external view override returns (LPPosition memory) {
        return _positions[key];
    }

    /// @notice Compute the position key for a given (pool, owner, range, salt) tuple.
    ///         Exposed so off-chain clients (frontend, scripts) and the test suite
    ///         can look up positions without re-deriving the formula.
    function positionKey(
        PoolId poolId,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt
    ) external pure returns (bytes32) {
        return _positionKey(poolId, owner, tickLower, tickUpper, salt);
    }

    // ---------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------

    function _ensurePoolInitialized(PoolId poolId) internal {
        if (_poolInitialized[poolId]) return;
        _poolInitialized[poolId] = true;
        _poolRiskState[poolId] = PoolRiskState({
            mode: RiskMode.LOW,
            volatilityScore: 0,
            reserveRatio: 0,
            seniorLiability: 0,
            juniorCollateral: 0,
            feeMultiplierBps: DEFAULT_FEE_MULTIPLIER_BPS,
            coverageRatioBps: DEFAULT_COVERAGE_RATIO_BPS,
            seniorDepositsEnabled: true,
            lastRiskUpdate: block.timestamp
        });
    }

    function _positionKey(
        PoolId poolId,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(poolId, owner, tickLower, tickUpper, salt));
    }

    function _abs(int128 x) private pure returns (uint256) {
        return uint256(uint128(x < 0 ? -x : x));
    }
}
