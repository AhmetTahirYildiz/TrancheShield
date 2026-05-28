// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AbstractCallback} from "@reactive-lib/abstract-base/AbstractCallback.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

import {ITrancheShieldHook} from "../interfaces/ITrancheShieldHook.sol";

/// @title CallbackReceiver
/// @notice Destination contract on Unichain Sepolia that receives Reactive Network
///         callbacks from the ReactiveRiskController (Lasna) and applies bounded
///         risk-parameter updates to the TrancheShieldHook (PROJECT-v2.md §8.4).
/// @dev    Every callback's first 160 bits are overwritten by Reactive Network with the
///         RVM ID, so the first parameter of each callback function MUST be `address rvmId`.
///         The `rvmIdOnly` modifier (from AbstractCallback) verifies both that the caller
///         is the Callback Proxy AND that `rvmId` matches the authorized RSC.
contract CallbackReceiver is AbstractCallback {
    /// @notice Bounds enforced on every parameter update. Protection stays partial by design.
    uint256 public constant MIN_FEE_MULTIPLIER_BPS = 10_000; // 1.00x
    uint256 public constant MAX_FEE_MULTIPLIER_BPS = 30_000; // 3.00x
    uint256 public constant MAX_COVERAGE_RATIO_BPS = 5_000;  // 50%

    /// @notice Highest valid RiskMode enum index (CRISIS == 3).
    uint8 public constant MAX_RISK_MODE = 3;

    ITrancheShieldHook public immutable hook;

    error FeeMultiplierOutOfBounds(uint256 bps);
    error CoverageRatioOutOfBounds(uint256 bps);
    error InvalidRiskMode(uint8 mode);

    event RiskParameterUpdated(bytes32 indexed parameter, bytes32 indexed poolId, uint256 value);

    /// @param _callbackProxy The Callback Proxy on Unichain Sepolia
    ///        (0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4).
    /// @param _hook          The TrancheShieldHook this receiver drives.
    constructor(address _callbackProxy, address _hook) AbstractCallback(_callbackProxy) payable {
        hook = ITrancheShieldHook(_hook);
    }

    /// @notice Set the pool's global risk mode. Triggered when volatility, reserve ratio,
    ///         or withdrawal-pressure thresholds are crossed on the RSC.
    /// @dev    `authorizedSenderOnly` ensures only the Callback Proxy can invoke this;
    ///         `rvmIdOnly` ensures the originating RSC's RVM ID is the authorized one.
    function setRiskMode(address rvmId, bytes32 poolId, uint8 newMode)
        external
        authorizedSenderOnly
        rvmIdOnly(rvmId)
    {
        if (newMode > MAX_RISK_MODE) revert InvalidRiskMode(newMode);
        hook.setRiskMode(PoolId.wrap(poolId), ITrancheShieldHook.RiskMode(newMode));
        emit RiskParameterUpdated("riskMode", poolId, newMode);
    }

    /// @notice Update the dynamic-fee multiplier (bps; 10_000 = 1.00x), bounded to
    ///         [MIN_FEE_MULTIPLIER_BPS, MAX_FEE_MULTIPLIER_BPS].
    function updateFeeMultiplier(address rvmId, bytes32 poolId, uint256 newBps)
        external
        authorizedSenderOnly
        rvmIdOnly(rvmId)
    {
        if (newBps < MIN_FEE_MULTIPLIER_BPS || newBps > MAX_FEE_MULTIPLIER_BPS) {
            revert FeeMultiplierOutOfBounds(newBps);
        }
        hook.updateFeeMultiplier(PoolId.wrap(poolId), newBps);
        emit RiskParameterUpdated("feeMultiplier", poolId, newBps);
    }

    /// @notice Update the IL coverage ratio (bps), capped at MAX_COVERAGE_RATIO_BPS (50%).
    function updateCoverageRatio(address rvmId, bytes32 poolId, uint256 newBps)
        external
        authorizedSenderOnly
        rvmIdOnly(rvmId)
    {
        if (newBps > MAX_COVERAGE_RATIO_BPS) revert CoverageRatioOutOfBounds(newBps);
        hook.updateCoverageRatio(PoolId.wrap(poolId), newBps);
        emit RiskParameterUpdated("coverageRatio", poolId, newBps);
    }

    /// @notice Enable or disable new Senior deposits on the pool.
    function setSeniorDepositStatus(address rvmId, bytes32 poolId, bool enabled)
        external
        authorizedSenderOnly
        rvmIdOnly(rvmId)
    {
        hook.setSeniorDepositStatus(PoolId.wrap(poolId), enabled);
        emit RiskParameterUpdated("seniorDeposits", poolId, enabled ? 1 : 0);
    }
}
