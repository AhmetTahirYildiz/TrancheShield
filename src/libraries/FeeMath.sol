// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";

/// @title FeeMath
/// @notice Dynamic-fee computation for TrancheShieldHook.
/// @dev    Multiplier is in bps (10_000 = 1.00x). Result is in pips (1_000_000 = 100%)
///         to match Uniswap v4's `LPFeeLibrary` units, capped at `MAX_LP_FEE`.
///         Bounds matching CallbackReceiver: multiplier ∈ [10_000, 30_000] bps.
library FeeMath {
    /// @dev Multiplier denominator. bps = basis points, 10_000 = 100%.
    uint256 internal constant MULTIPLIER_DENOMINATOR = 10_000;

    /// @notice Lower bound for the multiplier (1.00x = baseline LOW mode).
    uint256 internal constant MIN_FEE_MULTIPLIER_BPS = 10_000;

    /// @notice Upper bound for the multiplier (3.00x = CRISIS + toxic-flow surcharge).
    uint256 internal constant MAX_FEE_MULTIPLIER_BPS = 30_000;

    /// @notice Compute the dynamic fee given a base pool fee and a risk-mode multiplier.
    /// @param baseFeePips      Base fee in pips (e.g. 3_000 = 30 bps).
    /// @param multiplierBps    Multiplier in bps (10_000 = 1.00x).
    /// @return feePips         Effective fee in pips, capped at `LPFeeLibrary.MAX_LP_FEE`.
    function computeDynamicFee(uint24 baseFeePips, uint256 multiplierBps)
        internal
        pure
        returns (uint24 feePips)
    {
        // Out-of-range multipliers are clamped rather than reverted so that a temporary
        // misconfiguration on the RNK side never bricks the pool. The CallbackReceiver
        // enforces strict bounds upstream; this is a defense-in-depth safety net.
        if (multiplierBps < MIN_FEE_MULTIPLIER_BPS) {
            multiplierBps = MIN_FEE_MULTIPLIER_BPS;
        } else if (multiplierBps > MAX_FEE_MULTIPLIER_BPS) {
            multiplierBps = MAX_FEE_MULTIPLIER_BPS;
        }

        uint256 scaled = (uint256(baseFeePips) * multiplierBps) / MULTIPLIER_DENOMINATOR;
        if (scaled > LPFeeLibrary.MAX_LP_FEE) {
            scaled = LPFeeLibrary.MAX_LP_FEE;
        }
        feePips = uint24(scaled);
    }
}
