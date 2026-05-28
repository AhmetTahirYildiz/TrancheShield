// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AbstractReactive} from "@reactive-lib/abstract-base/AbstractReactive.sol";
import {IReactive} from "@reactive-lib/interfaces/IReactive.sol";

import {WelfordVolatility} from "../libraries/WelfordVolatility.sol";

/// @title ReactiveRiskController
/// @notice Reactive Smart Contract deployed to Lasna. The stateful risk brain of
///         TrancheShield (PROJECT-v2.md §8.3, §9). Subscribes to swap, reserve, and
///         Senior-withdrawal events on Unichain Sepolia (plus an optional Cron event),
///         maintains a rolling-window volatility estimate in its RVM state, and emits
///         bounded cross-chain callbacks to the CallbackReceiver when thresholds cross.
/// @dev    Runs in two environments: the RNK instance (constructor subscriptions, admin
///         setters via `rnOnly`) and the RVM instance (`react()` via `vmOnly`).
///         CRITICAL: `react()` is gated with `vmOnly` ONLY. Adding `authorizedSenderOnly`
///         silently breaks the roundtrip — the RVM caller is not in the senders ACL.
///         (Validated the hard way in the Phase-1 Hello World playground.)
contract ReactiveRiskController is AbstractReactive {
    using WelfordVolatility for WelfordVolatility.VolatilityState;

    // ---------------------------------------------------------------------
    // Risk mode mirror (matches ITrancheShieldHook.RiskMode ordering)
    // ---------------------------------------------------------------------

    enum RiskMode {
        LOW,
        MEDIUM,
        HIGH,
        CRISIS
    }

    // ---------------------------------------------------------------------
    // Configuration (immutable; consistent across RNK and RVM)
    // ---------------------------------------------------------------------

    uint256 public constant UNICHAIN_SEPOLIA_CHAIN_ID = 1301;
    uint256 public constant REACTIVE_CHAIN_ID = 5318007;
    uint64 public constant CALLBACK_GAS_LIMIT = 250_000;

    /// @dev Volatility scaling so a small raw tick stdev still produces a meaningful
    ///      score against the LOW/MEDIUM/HIGH/CRISIS thresholds.
    uint256 public constant VOLATILITY_SCALE = 1;

    /// @dev Fee multipliers (bps) by mode. PROJECT-v2.md §9.3 / §11.1.
    uint256 public constant FEE_MULT_LOW    = 10_000; // 1.00x
    uint256 public constant FEE_MULT_MEDIUM = 12_500; // 1.25x
    uint256 public constant FEE_MULT_HIGH   = 17_500; // 1.75x
    uint256 public constant FEE_MULT_CRISIS = 25_000; // 2.50x
    uint256 public constant FEE_MULT_MAX    = 30_000; // 3.00x hard ceiling
    uint256 public constant TOXIC_SURCHARGE_BPS = 2_500; // +0.25x

    /// @dev Consecutive same-direction swaps before the toxic-flow surcharge engages.
    uint256 public constant TOXIC_THRESHOLD = 3;

    /// @dev Minimum RVM blocks between callback bursts (anti-spam / cost control).
    uint256 public constant RATE_LIMIT_BLOCKS = 2;

    address public immutable hookAddress;
    address public immutable reserveAddress;
    address public immutable callbackReceiver;

    uint256 public immutable swapTopic0;
    uint256 public immutable reserveTopic0;
    uint256 public immutable withdrawTopic0;
    uint256 public immutable cronTopic0; // 0 disables the Cron subscription

    // ---------------------------------------------------------------------
    // RVM state — mutated by react()
    // ---------------------------------------------------------------------

    WelfordVolatility.VolatilityState internal vol;
    RiskMode public currentRiskMode;
    uint256 public currentFeeMultiplier;
    uint256 public lastCallbackBlock;
    uint256 public reactCount; // diagnostics

    // Toxic-flow tracking.
    int256 internal lastTickAfter;
    bool internal hasLastTick;
    int8 internal lastDirection; // -1, 0, +1
    uint256 internal consecutiveDirectional;

    // Bank-run detection: ring buffer of recent Senior-withdrawal timestamps.
    uint256 internal constant WITHDRAW_BUFFER = 16;
    uint256[16] internal withdrawalTimestamps;
    uint256 internal withdrawalIndex;

    // ---------------------------------------------------------------------
    // RNK state — admin-tunable thresholds (rnOnly)
    // ---------------------------------------------------------------------

    uint256 public volMediumThreshold = 50;
    uint256 public volHighThreshold = 150;
    uint256 public volCrisisThreshold = 300;

    uint256 public reserveCriticalThreshold = 7_000;  // 70%
    uint256 public reserveWeakThreshold = 10_000;     // 100%
    uint256 public reserveModerateThreshold = 15_000; // 150%

    uint256 public bankRunWindowSeconds = 3_600;
    uint256 public bankRunThreshold = 5;

    address public admin;

    // ---------------------------------------------------------------------
    // Events (RVM-side diagnostics; the cross-chain effect is `Callback`)
    // ---------------------------------------------------------------------

    event Subscribed(uint256 indexed chainId, address indexed origin, uint256 topic0);
    event Reacted(uint256 indexed topic0, bytes32 indexed poolId);
    event RiskModeComputed(bytes32 indexed poolId, RiskMode mode, uint256 volatilityScore, uint256 feeMultiplier);
    event BankRunDetected(bytes32 indexed poolId, uint256 withdrawalsInWindow);

    error NotAdmin();

    modifier onlyAdmin() {
        // Admin lives on the RNK side; `rnOnly` ensures we never mutate config in the RVM.
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    constructor(
        address _hook,
        address _reserve,
        address _callbackReceiver,
        uint256 _swapTopic0,
        uint256 _reserveTopic0,
        uint256 _withdrawTopic0,
        uint256 _cronTopic0
    ) payable {
        hookAddress = _hook;
        reserveAddress = _reserve;
        callbackReceiver = _callbackReceiver;
        swapTopic0 = _swapTopic0;
        reserveTopic0 = _reserveTopic0;
        withdrawTopic0 = _withdrawTopic0;
        cronTopic0 = _cronTopic0;

        admin = msg.sender;
        currentRiskMode = RiskMode.LOW;
        currentFeeMultiplier = FEE_MULT_LOW;

        // Subscriptions live on the RNK instance only. The RVM instance has no service.
        if (!vm) {
            service.subscribe(UNICHAIN_SEPOLIA_CHAIN_ID, _hook, _swapTopic0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
            emit Subscribed(UNICHAIN_SEPOLIA_CHAIN_ID, _hook, _swapTopic0);

            service.subscribe(UNICHAIN_SEPOLIA_CHAIN_ID, _reserve, _reserveTopic0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
            emit Subscribed(UNICHAIN_SEPOLIA_CHAIN_ID, _reserve, _reserveTopic0);

            service.subscribe(UNICHAIN_SEPOLIA_CHAIN_ID, _hook, _withdrawTopic0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
            emit Subscribed(UNICHAIN_SEPOLIA_CHAIN_ID, _hook, _withdrawTopic0);

            if (_cronTopic0 != 0) {
                service.subscribe(REACTIVE_CHAIN_ID, address(SERVICE_ADDR), _cronTopic0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
                emit Subscribed(REACTIVE_CHAIN_ID, address(SERVICE_ADDR), _cronTopic0);
            }
        }
    }

    // ---------------------------------------------------------------------
    // react() — RVM entry point. vmOnly ONLY (see contract-level note).
    // ---------------------------------------------------------------------

    function react(LogRecord calldata log) external vmOnly {
        unchecked {
            ++reactCount;
        }
        uint256 t0 = log.topic_0;
        bytes32 poolId = bytes32(log.topic_1);
        emit Reacted(t0, poolId);

        if (t0 == swapTopic0) {
            _onSwap(poolId, log);
        } else if (t0 == reserveTopic0) {
            _onReserveRatio(poolId, log);
        } else if (t0 == withdrawTopic0) {
            _onSeniorWithdrawal(poolId, log);
        } else if (cronTopic0 != 0 && t0 == cronTopic0) {
            _onCron(poolId);
        }
        // Unknown topics are silently ignored.
    }

    // ---------------------------------------------------------------------
    // Per-event handlers
    // ---------------------------------------------------------------------

    function _onSwap(bytes32 poolId, LogRecord calldata log) internal {
        // SwapRiskObserved(bytes32 indexed poolId, int24 tickBefore, int24 tickAfter,
        //                   uint256 amountIn, uint256 amountOut, uint256 timestamp)
        (int24 tickBefore, int24 tickAfter,,,) =
            abi.decode(log.data, (int24, int24, uint256, uint256, uint256));

        vol.update(int256(tickAfter));
        _trackDirection(tickBefore, tickAfter);

        uint256 score = WelfordVolatility.stdevScaled(vol.count, vol.sum, vol.sumSq, VOLATILITY_SCALE);
        (RiskMode newMode, uint256 newMultiplier) = _classify(score);

        emit RiskModeComputed(poolId, newMode, score, newMultiplier);

        if (newMode != currentRiskMode && _rateLimitOk()) {
            _emitModeChange(poolId, newMode, newMultiplier);
        }
    }

    function _onReserveRatio(bytes32 poolId, LogRecord calldata log) internal {
        // ReserveRatioUpdated(bytes32 indexed poolId, uint256 reserveBalance,
        //                     uint256 seniorLiability, uint256 reserveRatioBps)
        (,, uint256 reserveRatioBps) = abi.decode(log.data, (uint256, uint256, uint256));

        uint256 newCoverage = 5_000; // 50% default
        bool critical = false;
        if (reserveRatioBps < reserveCriticalThreshold) {
            newCoverage = 1_000; // 10%
            critical = true;
        } else if (reserveRatioBps < reserveWeakThreshold) {
            newCoverage = 2_000; // 20%
        } else if (reserveRatioBps < reserveModerateThreshold) {
            newCoverage = 3_500; // 35%
        }

        if (!_rateLimitOk()) return;
        lastCallbackBlock = block.number;

        _callback(abi.encodeWithSignature("updateCoverageRatio(address,bytes32,uint256)", address(0), poolId, newCoverage));

        if (critical) {
            currentRiskMode = RiskMode.CRISIS;
            currentFeeMultiplier = FEE_MULT_CRISIS;
            _callback(abi.encodeWithSignature("setRiskMode(address,bytes32,uint8)", address(0), poolId, uint8(RiskMode.CRISIS)));
            _callback(abi.encodeWithSignature("setSeniorDepositStatus(address,bytes32,bool)", address(0), poolId, false));
        }
    }

    function _onSeniorWithdrawal(bytes32 poolId, LogRecord calldata log) internal {
        // SeniorWithdrawalRequested(bytes32 indexed poolId, address indexed owner,
        //                           uint256 liquidity, uint256 timestamp)
        (, uint256 timestamp) = abi.decode(log.data, (uint256, uint256));

        withdrawalTimestamps[withdrawalIndex] = timestamp;
        unchecked {
            withdrawalIndex = (withdrawalIndex + 1) % WITHDRAW_BUFFER;
        }

        uint256 inWindow = _countWithdrawalsInWindow(timestamp);
        if (inWindow >= bankRunThreshold && _rateLimitOk()) {
            emit BankRunDetected(poolId, inWindow);
            currentRiskMode = RiskMode.CRISIS;
            currentFeeMultiplier = FEE_MULT_CRISIS;
            lastCallbackBlock = block.number;
            _callback(abi.encodeWithSignature("setRiskMode(address,bytes32,uint8)", address(0), poolId, uint8(RiskMode.CRISIS)));
            _callback(abi.encodeWithSignature("updateCoverageRatio(address,bytes32,uint256)", address(0), poolId, uint256(1_500)));
            _callback(abi.encodeWithSignature("setSeniorDepositStatus(address,bytes32,bool)", address(0), poolId, false));
        }
    }

    function _onCron(bytes32 poolId) internal {
        // Periodic re-evaluation: lets risk modes decay back toward LOW during quiet
        // periods with no swaps. Recompute from the existing window.
        uint256 score = WelfordVolatility.stdevScaled(vol.count, vol.sum, vol.sumSq, VOLATILITY_SCALE);
        (RiskMode newMode, uint256 newMultiplier) = _classify(score);
        if (newMode != currentRiskMode && _rateLimitOk()) {
            _emitModeChange(poolId, newMode, newMultiplier);
        }
    }

    // ---------------------------------------------------------------------
    // Classification + helpers
    // ---------------------------------------------------------------------

    function _classify(uint256 score) internal view returns (RiskMode mode, uint256 multiplier) {
        if (score >= volCrisisThreshold) {
            mode = RiskMode.CRISIS;
            multiplier = FEE_MULT_CRISIS;
        } else if (score >= volHighThreshold) {
            mode = RiskMode.HIGH;
            multiplier = FEE_MULT_HIGH;
        } else if (score >= volMediumThreshold) {
            mode = RiskMode.MEDIUM;
            multiplier = FEE_MULT_MEDIUM;
        } else {
            mode = RiskMode.LOW;
            multiplier = FEE_MULT_LOW;
        }

        // Toxic-flow surcharge: persistent one-directional flow makes the pool more
        // expensive to sweep, capped at the global 3.00x ceiling.
        if (consecutiveDirectional >= TOXIC_THRESHOLD) {
            multiplier += TOXIC_SURCHARGE_BPS;
            if (multiplier > FEE_MULT_MAX) multiplier = FEE_MULT_MAX;
        }
    }

    function _emitModeChange(bytes32 poolId, RiskMode newMode, uint256 newMultiplier) internal {
        currentRiskMode = newMode;
        currentFeeMultiplier = newMultiplier;
        lastCallbackBlock = block.number;
        _callback(abi.encodeWithSignature("setRiskMode(address,bytes32,uint8)", address(0), poolId, uint8(newMode)));
        _callback(abi.encodeWithSignature("updateFeeMultiplier(address,bytes32,uint256)", address(0), poolId, newMultiplier));
    }

    function _callback(bytes memory payload) internal {
        emit Callback(UNICHAIN_SEPOLIA_CHAIN_ID, callbackReceiver, CALLBACK_GAS_LIMIT, payload);
    }

    function _trackDirection(int24 tickBefore, int24 tickAfter) internal {
        int8 dir = tickAfter > tickBefore ? int8(1) : (tickAfter < tickBefore ? int8(-1) : int8(0));
        if (dir != 0 && hasLastTick && dir == lastDirection) {
            unchecked {
                ++consecutiveDirectional;
            }
        } else {
            consecutiveDirectional = dir == 0 ? 0 : 1;
        }
        lastDirection = dir;
        lastTickAfter = int256(tickAfter);
        hasLastTick = true;
    }

    function _countWithdrawalsInWindow(uint256 nowTs) internal view returns (uint256 n) {
        uint256 cutoff = nowTs > bankRunWindowSeconds ? nowTs - bankRunWindowSeconds : 0;
        for (uint256 i = 0; i < WITHDRAW_BUFFER; i++) {
            uint256 ts = withdrawalTimestamps[i];
            if (ts != 0 && ts >= cutoff && ts <= nowTs) {
                unchecked {
                    ++n;
                }
            }
        }
    }

    function _rateLimitOk() internal view returns (bool) {
        return block.number > lastCallbackBlock + RATE_LIMIT_BLOCKS;
    }

    // ---------------------------------------------------------------------
    // Views (diagnostics / frontend)
    // ---------------------------------------------------------------------

    function volatilityScore() external view returns (uint256) {
        return WelfordVolatility.stdevScaled(vol.count, vol.sum, vol.sumSq, VOLATILITY_SCALE);
    }

    function sampleCount() external view returns (uint256) {
        return vol.count;
    }

    // ---------------------------------------------------------------------
    // Admin (RNK side; rnOnly + onlyAdmin)
    // ---------------------------------------------------------------------

    function setVolatilityThresholds(uint256 medium, uint256 high, uint256 crisis) external rnOnly onlyAdmin {
        volMediumThreshold = medium;
        volHighThreshold = high;
        volCrisisThreshold = crisis;
    }

    function setReserveThresholds(uint256 critical, uint256 weak, uint256 moderate) external rnOnly onlyAdmin {
        reserveCriticalThreshold = critical;
        reserveWeakThreshold = weak;
        reserveModerateThreshold = moderate;
    }

    function setBankRunParams(uint256 windowSeconds, uint256 threshold) external rnOnly onlyAdmin {
        bankRunWindowSeconds = windowSeconds;
        bankRunThreshold = threshold;
    }

    function transferAdmin(address newAdmin) external rnOnly onlyAdmin {
        admin = newAdmin;
    }
}
