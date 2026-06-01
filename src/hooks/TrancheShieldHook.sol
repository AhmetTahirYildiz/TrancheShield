// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/utils/BaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";

import {ITrancheShieldHook} from "../interfaces/ITrancheShieldHook.sol";
import {IProtectionReserve} from "../interfaces/IProtectionReserve.sol";
import {FeeMath} from "../libraries/FeeMath.sol";
import {ILMath} from "../libraries/ILMath.sol";

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

    /// @notice Base fee in pips (Uniswap v4 LP-fee units; 1_000_000 = 100%).
    ///         3_000 = 30 bps. PROJECT-v2.md §11 uses 30 bps as the LOW-mode anchor.
    ///         Hardcoded for MVP simplicity — future work makes it per-pool configurable.
    uint24 internal constant BASE_FEE_PIPS = 3_000;

    /// @notice Per-position coverage cap, in bps of the position's `entryValueToken1`.
    ///         PROJECT-v2.md §13: 20% of deposit.
    uint256 internal constant PER_POSITION_COVERAGE_CAP_BPS = 2_000;

    /// @notice Per-event Junior-tier waterfall cap, in bps of the pool's `juniorCollateral`.
    ///         PROJECT-v2.md §8.5: prevents a single Senior exit from draining Junior.
    uint256 internal constant JUNIOR_PER_EVENT_CAP_BPS = 2_000;

    /// @notice Premium split tables (in bps; first entry = active LP share, second = reserve,
    ///         third = Junior premium). Indexed by RiskMode. PROJECT-v2.md §12.
    uint256 private constant LP_SHARE_LOW_BPS      = 8_000;
    uint256 private constant RESERVE_SHARE_LOW_BPS = 1_000;
    uint256 private constant LP_SHARE_MED_BPS      = 7_000;
    uint256 private constant RESERVE_SHARE_MED_BPS = 2_000;
    uint256 private constant LP_SHARE_HIGH_BPS      = 6_000;
    uint256 private constant RESERVE_SHARE_HIGH_BPS = 2_500;
    uint256 private constant LP_SHARE_CRISIS_BPS      = 5_000;
    uint256 private constant RESERVE_SHARE_CRISIS_BPS = 3_500;

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error InvalidHookData();
    error SeniorDepositsDisabled();
    error PositionNotFound();
    error PositionAlreadyClosed();
    error NotCallbackReceiver();
    error NotAdmin();
    error ZeroAddress();
    error LiquidityDeltaInvalid();

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    IProtectionReserve public immutable reserve;

    /// @notice Admin authorized to (re)point the hook at a CallbackReceiver. Set at
    ///         construction. Kept updatable so a receiver bug-fix never forces re-mining
    ///         the hook address.
    address public admin;

    /// @notice Destination CallbackReceiver allowed to drive the risk-parameter setters.
    address public callbackReceiver;

    mapping(PoolId => PoolRiskState) internal _poolRiskState;
    mapping(bytes32 => LPPosition) internal _positions;

    /// @dev True once the pool has been touched and its risk state is initialized.
    mapping(PoolId => bool) internal _poolInitialized;

    /// @dev Pre-swap tick snapshot, populated in `beforeSwap` and consumed in `afterSwap`
    ///      to emit `SwapRiskObserved(tickBefore, tickAfter, ...)` for the Reactive RSC.
    mapping(PoolId => int24) internal _tickBeforeSwap;

    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------

    modifier onlyCallbackReceiver() {
        if (msg.sender != callbackReceiver) revert NotCallbackReceiver();
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    // ---------------------------------------------------------------------
    // Constructor / init
    // ---------------------------------------------------------------------

    /// @param _admin Address allowed to (re)set the CallbackReceiver. Passed explicitly
    ///        because the hook is deployed via CREATE2 (constructor `msg.sender` is the
    ///        factory, not the operator).
    constructor(IPoolManager _poolManager, IProtectionReserve _reserve, address _admin) BaseHook(_poolManager) {
        if (address(_reserve) == address(0) || _admin == address(0)) revert ZeroAddress();
        reserve = _reserve;
        admin = _admin;
    }

    /// @notice Point the hook at its CallbackReceiver. The receiver is deployed after the
    ///         hook (it depends on the hook address), so we wire it post-construction.
    ///         Updatable by `admin` so a receiver bug-fix doesn't force re-mining the hook.
    function setCallbackReceiver(address _receiver) external onlyAdmin {
        if (_receiver == address(0)) revert ZeroAddress();
        callbackReceiver = _receiver;
    }

    /// @notice Transfer the admin role (e.g. to a multisig post-launch).
    function setAdmin(address _admin) external onlyAdmin {
        if (_admin == address(0)) revert ZeroAddress();
        admin = _admin;
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

        // Token1-denominated entry value (PROJECT-v2.md §13). Used by IL math at exit
        // and to size each position's `perPositionCoverageCap`.
        uint256 entryValueToken1 = ILMath.computeHodlValue(amount0, amount1, sqrtPriceX96);

        _positions[posKey] = LPPosition({
            owner: owner,
            tranche: tranche,
            liquidity: uint256(params.liquidityDelta),
            depositedAmount0: amount0,
            depositedAmount1: amount1,
            entryValueToken1: entryValueToken1,
            entrySqrtPriceX96: sqrtPriceX96,
            entryTick: tick,
            entryTimestamp: block.timestamp,
            active: true
        });

        // Senior liability = `perPositionCoverageCap` (20% of entry value).
        // Junior collateral = full entry value (Junior LPs underwrite at face value).
        if (tranche == Tranche.SENIOR) {
            uint256 cap = (entryValueToken1 * PER_POSITION_COVERAGE_CAP_BPS) / 10_000;
            _poolRiskState[poolId].seniorLiability += cap;
            reserve.increaseSeniorLiability(poolId, owner, cap);
        } else {
            _poolRiskState[poolId].juniorCollateral += entryValueToken1;
            reserve.increaseJuniorCollateral(poolId, owner, entryValueToken1);
        }

        emit PositionOpened(posKey, owner, poolId, tranche, uint256(params.liquidityDelta), entryValueToken1);

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
        BalanceDelta delta,
        BalanceDelta, /* feesAccrued */
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        (, address owner) = abi.decode(hookData, (Tranche, address));
        PoolId poolId = key.toId();
        bytes32 posKey = _positionKey(poolId, owner, params.tickLower, params.tickUpper, params.salt);

        LPPosition storage position = _positions[posKey];
        if (!position.active) revert PositionAlreadyClosed();

        // Phase 3: single-shot full close. Partial withdrawals are future work.
        position.active = false;

        (uint256 ilShortfall, uint256 compensation) = _settleSeniorOrJunior(
            poolId,
            key.currency1,
            owner,
            position,
            delta
        );

        emit PositionClosed(posKey, owner, poolId, ilShortfall, compensation);

        return (IHooks.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    /// @dev Splits the close path between Senior (IL + waterfall + payout) and Junior
    ///     (collateral release) so `_afterRemoveLiquidity` stays under stack-too-deep.
    function _settleSeniorOrJunior(
        PoolId poolId,
        Currency currency1,
        address owner,
        LPPosition storage position,
        BalanceDelta delta
    ) internal returns (uint256 ilShortfall, uint256 compensation) {
        if (position.tranche == Tranche.SENIOR) {
            (ilShortfall, compensation) = _settleSenior(poolId, currency1, owner, position, delta);
        } else {
            _settleJunior(poolId, owner, position);
        }
    }

    function _settleSenior(
        PoolId poolId,
        Currency currency1,
        address owner,
        LPPosition storage position,
        BalanceDelta delta
    ) internal returns (uint256 ilShortfall, uint256 compensation) {
        // 1) Read pool exit price.
        (uint160 sqrtPriceX96Exit,,,) = poolManager.getSlot0(poolId);

        // 2) Compute IL. Pool returns positive deltas to the LP on exit.
        uint256 amount0Exit = _abs(BalanceDeltaLibrary.amount0(delta));
        uint256 amount1Exit = _abs(BalanceDeltaLibrary.amount1(delta));
        uint256 hodl = ILMath.computeHodlValue(position.depositedAmount0, position.depositedAmount1, sqrtPriceX96Exit);
        uint256 exitVal = ILMath.computeLPExitValue(amount0Exit, amount1Exit, sqrtPriceX96Exit);
        ilShortfall = ILMath.computeILShortfall(hodl, exitVal);

        // 3) Always release the Senior liability bookkeeping, even when IL is zero.
        PoolRiskState storage state = _poolRiskState[poolId];
        uint256 perPositionCap = (position.entryValueToken1 * PER_POSITION_COVERAGE_CAP_BPS) / 10_000;
        state.seniorLiability -= perPositionCap;
        reserve.decreaseSeniorLiability(poolId, owner, perPositionCap);

        if (ilShortfall == 0) return (0, 0);

        // 4) Apply coverage ratio, then the per-position cap (PROJECT-v2.md §13).
        uint256 desired = (ilShortfall * state.coverageRatioBps) / 10_000;
        if (desired > perPositionCap) desired = perPositionCap;

        // 5) Waterfall: drain reserve (Tier 1), then Junior collateral (Tier 2, capped per event).
        uint256 reserveBalance = reserve.getReserveBalance(poolId, currency1);
        uint256 fromReserve = desired <= reserveBalance ? desired : reserveBalance;
        uint256 remaining = desired - fromReserve;

        uint256 fromJunior = 0;
        if (remaining > 0) {
            uint256 juniorCap = (state.juniorCollateral * JUNIOR_PER_EVENT_CAP_BPS) / 10_000;
            fromJunior = remaining <= juniorCap ? remaining : juniorCap;
            if (fromJunior > state.juniorCollateral) fromJunior = state.juniorCollateral;
        }

        compensation = fromReserve + fromJunior;

        // 6) Execute payouts. Reserve handles its own currency transfer; Junior draw is
        //    bookkeeping-only in Phase 3 (real Junior-side debit lands in Phase 4 along
        //    with full fee-routing plumbing).
        if (fromReserve > 0) {
            reserve.payCompensation(poolId, owner, currency1, fromReserve);
        }
        if (fromJunior > 0) {
            state.juniorCollateral -= fromJunior;
            // No single Junior owner to charge in MVP; aggregate-only debit suffices.
        }
    }

    function _settleJunior(PoolId poolId, address owner, LPPosition storage position) internal {
        _poolRiskState[poolId].juniorCollateral -= position.entryValueToken1;
        reserve.decreaseJuniorCollateral(poolId, owner, position.entryValueToken1);
    }

    // ---------------------------------------------------------------------
    // Swap hooks — Phase 3 will fill these in (dynamic fee + premium routing)
    // ---------------------------------------------------------------------

    function _beforeSwap(
        address, /* sender */
        PoolKey calldata key,
        SwapParams calldata, /* params */
        bytes calldata /* hookData */
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId poolId = key.toId();
        _ensurePoolInitialized(poolId);

        // Snapshot the entry tick so `afterSwap` can emit `SwapRiskObserved` with both.
        (, int24 tickBefore,,) = poolManager.getSlot0(poolId);
        _tickBeforeSwap[poolId] = tickBefore;

        // Compute the dynamic fee from the live multiplier and OR in OVERRIDE_FEE_FLAG so
        // PoolManager applies it to this swap (requires the pool to be dynamic-fee).
        uint24 feePips = FeeMath.computeDynamicFee(BASE_FEE_PIPS, _poolRiskState[poolId].feeMultiplierBps);
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, feePips | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    function _afterSwap(
        address, /* sender */
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata /* hookData */
    ) internal override returns (bytes4, int128) {
        PoolId poolId = key.toId();
        (, int24 tickAfter,,) = poolManager.getSlot0(poolId);
        int24 tickBefore = _tickBeforeSwap[poolId];

        // Magnitudes for telemetry and the premium computation. `amountSpecified` is the
        // user-requested side; the opposite side is whatever the pool returned.
        uint256 amountIn = uint256(int256(params.amountSpecified < 0 ? -params.amountSpecified : params.amountSpecified));
        uint256 amountOut = _swapOutputMagnitude(params, delta);

        emit SwapRiskObserved(poolId, tickBefore, tickAfter, amountIn, amountOut, block.timestamp);

        // Premium routing: feePips × amountIn yields the fee taken by the pool; the
        // reserve-share fraction is what TrancheShield siphons. Phase-3 implementation
        // is bookkeeping-only — actual fee skim via hook-deltas lands in Phase 4.
        uint256 feePips = FeeMath.computeDynamicFee(BASE_FEE_PIPS, _poolRiskState[poolId].feeMultiplierBps);
        uint256 grossFee = (amountIn * feePips) / 1_000_000;
        uint256 reserveShareBps = _reserveShareBps(_poolRiskState[poolId].mode);
        uint256 premium = (grossFee * reserveShareBps) / 10_000;

        if (premium > 0) {
            // Fee is taken in the input currency.
            Currency premiumCurrency = params.zeroForOne ? key.currency0 : key.currency1;
            reserve.routePremium(poolId, premiumCurrency, premium);
        }

        return (IHooks.afterSwap.selector, 0);
    }

    function _swapOutputMagnitude(SwapParams calldata params, BalanceDelta delta) internal pure returns (uint256) {
        // For zeroForOne, the LP/swapper receives currency1 → use amount1; otherwise amount0.
        int128 outDelta = params.zeroForOne ? BalanceDeltaLibrary.amount1(delta) : BalanceDeltaLibrary.amount0(delta);
        return _abs(outDelta);
    }

    function _reserveShareBps(RiskMode mode) internal pure returns (uint256) {
        if (mode == RiskMode.CRISIS) return RESERVE_SHARE_CRISIS_BPS;
        if (mode == RiskMode.HIGH) return RESERVE_SHARE_HIGH_BPS;
        if (mode == RiskMode.MEDIUM) return RESERVE_SHARE_MED_BPS;
        return RESERVE_SHARE_LOW_BPS;
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

        // Hard safety coupling: CRISIS always halts new Senior deposits, so the
        // "CRISIS ⇒ !seniorDepositsEnabled" invariant holds regardless of callback
        // ordering on the RSC side.
        if (newMode == RiskMode.CRISIS && state.seniorDepositsEnabled) {
            state.seniorDepositsEnabled = false;
            emit SeniorDepositStatusChanged(poolId, false);
        }

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
