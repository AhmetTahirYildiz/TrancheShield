// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";

/// @title IProtectionReserve
/// @notice External surface of the per-pool IL Protection Reserve.
/// @dev    Two distinct caller groups:
///         - The TrancheShieldHook calls the mutating functions during the swap
///           and liquidity lifecycle (premium routing, compensation payout,
///           liability/collateral bookkeeping).
///         - The Reactive Network RSC subscribes to `ReserveRatioUpdated` to
///           drive coverage-ratio and risk-mode adjustments (§9.3).
///
///         Reserves track balances per (poolId, currency) because a v4 swap fee
///         can land in either token of the pair depending on swap direction.
///         Senior liability and Junior collateral are tracked per pool as
///         token1-denominated scalar accumulators (see PROJECT-v2.md §13).
interface IProtectionReserve {
    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event PremiumRouted(PoolId indexed poolId, Currency indexed currency, uint256 amount);

    event CompensationPaid(
        PoolId indexed poolId,
        address indexed recipient,
        Currency indexed currency,
        uint256 amount
    );

    /// @notice Emitted after any change to reserve balance, Senior liability, or
    ///         Junior collateral that alters the solvency ratios. Reactive RSC
    ///         subscribes to this topic on Lasna and emits `updateCoverageRatio`
    ///         and `setRiskMode` callbacks as thresholds are crossed.
    event ReserveRatioUpdated(
        PoolId indexed poolId,
        uint256 reserveBalanceToken1Equivalent,
        uint256 seniorLiability,
        uint256 reserveRatioBps
    );

    event SeniorLiabilityIncreased(
        PoolId indexed poolId,
        address indexed owner,
        uint256 amount,
        uint256 newTotal
    );

    event SeniorLiabilityDecreased(
        PoolId indexed poolId,
        address indexed owner,
        uint256 amount,
        uint256 newTotal
    );

    event JuniorCollateralIncreased(
        PoolId indexed poolId,
        address indexed owner,
        uint256 amount,
        uint256 newTotal
    );

    event JuniorCollateralDecreased(
        PoolId indexed poolId,
        address indexed owner,
        uint256 amount,
        uint256 newTotal
    );

    // ---------------------------------------------------------------------
    // Mutating functions — hook-only
    // ---------------------------------------------------------------------

    /// @notice Credit the reserve with a swap-fee premium. Pulled from the hook
    ///         in `afterSwap` after the protocol's split (§12) is computed.
    /// @dev    The hook is expected to have transferred `amount` of `currency` to
    ///         this contract before (or atomically with) the call.
    function routePremium(PoolId poolId, Currency currency, uint256 amount) external;

    /// @notice Pay compensation from the reserve to a Senior LP on withdrawal.
    ///         The hook computes the waterfall (§8.5) and calls this for the
    ///         Tier 1 portion drawn from the reserve.
    /// @dev    Reverts if the reserve balance for `(poolId, currency)` is below
    ///         `amount`. The hook is responsible for clamping to available
    ///         capacity before calling.
    function payCompensation(
        PoolId poolId,
        address recipient,
        Currency currency,
        uint256 amount
    ) external;

    /// @notice Track Senior insurance liability. Increases on Senior deposit by
    ///         the position's `perPositionCoverageCap` (§13).
    function increaseSeniorLiability(PoolId poolId, address owner, uint256 amount) external;

    /// @notice Decreases on Senior withdrawal (full or partial).
    function decreaseSeniorLiability(PoolId poolId, address owner, uint256 amount) external;

    /// @notice Track Junior first-loss collateral. Increases on Junior deposit.
    function increaseJuniorCollateral(PoolId poolId, address owner, uint256 amount) external;

    /// @notice Decreases on Junior withdrawal OR when Tier 2 of the waterfall is
    ///         drawn down to cover Senior compensation.
    function decreaseJuniorCollateral(PoolId poolId, address owner, uint256 amount) external;

    // ---------------------------------------------------------------------
    // View functions
    // ---------------------------------------------------------------------

    /// @notice Raw reserve balance for a specific (pool, currency) bucket.
    function getReserveBalance(PoolId poolId, Currency currency) external view returns (uint256);

    /// @notice Aggregate Senior liability across all active Senior positions in the pool.
    function getSeniorLiability(PoolId poolId) external view returns (uint256);

    /// @notice Aggregate Junior collateral across all active Junior positions in the pool.
    function getJuniorCollateral(PoolId poolId) external view returns (uint256);

    /// @notice Reserve-to-liability ratio in bps. Returns `type(uint256).max` when
    ///         `seniorLiability == 0` to encode "no obligations → trivially solvent".
    function getReserveRatioBps(PoolId poolId) external view returns (uint256);
}
