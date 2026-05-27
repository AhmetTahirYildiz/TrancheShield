// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "v4-core/types/PoolId.sol";

/// @title ITrancheShieldHook
/// @notice External surface of the TrancheShield Uniswap v4 hook.
/// @dev    Defines the API that off-hook actors interact with:
///         - LPs (event surface for position open/close)
///         - CallbackReceiver on Unichain Sepolia (admin setters invoked by Reactive callbacks)
///         - Reactive Network RSC on Lasna (event topics it subscribes to)
///         - Frontend / external readers (view functions)
///
///         Hook lifecycle entrypoints (`beforeAddLiquidity`, `afterSwap`, etc.) are
///         inherited from `BaseHook` and intentionally not part of this interface — the
///         PoolManager is the only legitimate caller and uses the IHooks interface directly.
interface ITrancheShieldHook {
    // ---------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------

    /// @notice LP tranche selection made at deposit time. Immutable per position.
    enum Tranche {
        SENIOR,
        JUNIOR
    }

    /// @notice Pool-level risk regime. Driven by the Reactive controller's
    ///         rolling-window volatility and reserve solvency signals.
    enum RiskMode {
        LOW,
        MEDIUM,
        HIGH,
        CRISIS
    }

    /// @notice Per-LP-position record. Stored at `afterAddLiquidity`, consumed at
    ///         `afterRemoveLiquidity` for IL and waterfall accounting.
    /// @dev    `positionKey` is the index outside this struct (typically
    ///         keccak256(owner, poolId, tickLower, tickUpper, salt)).
    struct LPPosition {
        address owner;
        Tranche tranche;
        uint256 liquidity;
        uint256 depositedAmount0;
        uint256 depositedAmount1;
        uint256 entryValueToken1;
        uint160 entrySqrtPriceX96;
        int24 entryTick;
        uint256 entryTimestamp;
        bool active;
    }

    /// @notice Per-pool risk state. Mutated by hook lifecycle hooks and by
    ///         Reactive callbacks via the four admin setters below.
    struct PoolRiskState {
        RiskMode mode;
        uint256 volatilityScore;
        uint256 reserveRatio;
        uint256 seniorLiability;
        uint256 juniorCollateral;
        uint256 feeMultiplierBps;
        uint256 coverageRatioBps;
        bool seniorDepositsEnabled;
        uint256 lastRiskUpdate;
    }

    // ---------------------------------------------------------------------
    // Events — position lifecycle
    // ---------------------------------------------------------------------

    event PositionOpened(
        bytes32 indexed positionKey,
        address indexed owner,
        PoolId indexed poolId,
        Tranche tranche,
        uint256 liquidity,
        uint256 entryValueToken1
    );

    event PositionClosed(
        bytes32 indexed positionKey,
        address indexed owner,
        PoolId indexed poolId,
        uint256 ilShortfall,
        uint256 compensationPaid
    );

    // ---------------------------------------------------------------------
    // Events — Reactive Network subscribes to these topics on the RNK side
    // ---------------------------------------------------------------------

    /// @notice Emitted in `afterSwap`. Drives the RSC's Welford rolling-window update.
    event SwapRiskObserved(
        PoolId indexed poolId,
        int24 tickBefore,
        int24 tickAfter,
        uint256 amountIn,
        uint256 amountOut,
        uint256 timestamp
    );

    /// @notice Emitted in `beforeRemoveLiquidity` when the exiting position is Senior.
    ///         RSC counts these in a rolling window for bank-run detection.
    event SeniorWithdrawalRequested(
        PoolId indexed poolId,
        address indexed owner,
        uint256 liquidity,
        uint256 timestamp
    );

    // ---------------------------------------------------------------------
    // Events — risk-parameter mutations (driven by Reactive callbacks)
    // ---------------------------------------------------------------------

    event RiskModeChanged(PoolId indexed poolId, RiskMode oldMode, RiskMode newMode);
    event FeeMultiplierUpdated(PoolId indexed poolId, uint256 oldBps, uint256 newBps);
    event CoverageRatioUpdated(PoolId indexed poolId, uint256 oldBps, uint256 newBps);
    event SeniorDepositStatusChanged(PoolId indexed poolId, bool enabled);

    // ---------------------------------------------------------------------
    // Admin setters — callable only by the CallbackReceiver
    // ---------------------------------------------------------------------

    /// @notice Set the pool's global risk mode (LOW/MEDIUM/HIGH/CRISIS).
    /// @dev    Caller MUST be the configured CallbackReceiver. Reverts otherwise.
    function setRiskMode(PoolId poolId, RiskMode newMode) external;

    /// @notice Update the dynamic-fee multiplier (in bps; 10_000 = 1.00x).
    /// @dev    CallbackReceiver enforces the [MIN_FEE_MULTIPLIER_BPS, MAX_FEE_MULTIPLIER_BPS]
    ///         range upstream — this function trusts its caller for the bounds check.
    function updateFeeMultiplier(PoolId poolId, uint256 newBps) external;

    /// @notice Update the IL coverage ratio (in bps; 5_000 = 50%, the protocol-wide ceiling).
    /// @dev    CallbackReceiver enforces the `MAX_COVERAGE_RATIO_BPS` ceiling upstream.
    function updateCoverageRatio(PoolId poolId, uint256 newBps) external;

    /// @notice Toggle whether new Senior deposits are accepted on this pool.
    /// @dev    Used to halt liability accrual when the system is undercollateralized.
    function setSeniorDepositStatus(PoolId poolId, bool enabled) external;

    // ---------------------------------------------------------------------
    // View functions
    // ---------------------------------------------------------------------

    /// @notice Returns the current risk state for a pool. Returns the zero value
    ///         struct if `poolId` is not initialized through this hook.
    function getPoolRiskState(PoolId poolId) external view returns (PoolRiskState memory);

    /// @notice Returns the LP position keyed by its position hash. `active == false`
    ///         indicates either a closed position or an unknown key.
    function getPosition(bytes32 positionKey) external view returns (LPPosition memory);
}
