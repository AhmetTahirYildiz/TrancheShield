// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {IProtectionReserve} from "../interfaces/IProtectionReserve.sol";

/// @title ProtectionReserve
/// @notice Per-pool IL Protection Reserve. Holds premium-routed funds that back
///         Senior LP impermanent-loss compensation, and tracks Senior liability
///         and Junior collateral accumulators alongside reserve balances.
/// @dev    Phase 2 scope: bookkeeping + custody only. Premium routing and
///         compensation payout are exercised live in Phase 3 from the hook's
///         `afterSwap` / `afterRemoveLiquidity` paths. The reserve assumes the
///         hook has already moved tokens to/from this contract before calling
///         `routePremium` / `payCompensation` — except for the outbound transfer
///         in `payCompensation`, which the reserve performs directly via
///         `CurrencyLibrary.transfer`.
contract ProtectionReserve is IProtectionReserve {
    using CurrencyLibrary for Currency;

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error NotHook();
    error HookAlreadySet();
    error ZeroAddress();
    error InsufficientReserve();
    error LiabilityUnderflow();
    error CollateralUnderflow();

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    /// @notice One-time set to the TrancheShieldHook address after both contracts deploy.
    address public hook;

    /// @notice Reserve balance per (pool, currency). Updated by `routePremium` /
    ///         `payCompensation`; deliberately separate from the contract's actual
    ///         token balance so internal accounting stays clean even if someone
    ///         force-sends tokens to the reserve.
    mapping(PoolId => mapping(Currency => uint256)) internal _reserveBalance;

    /// @notice Aggregate Senior liability per pool (token1-denominated; see PROJECT-v2.md §13).
    mapping(PoolId => uint256) internal _seniorLiability;

    /// @notice Per-LP Senior liability for dashboard/queryability. Sum across all owners
    ///         in a pool MUST equal `_seniorLiability[poolId]`.
    mapping(PoolId => mapping(address => uint256)) internal _seniorLiabilityByOwner;

    /// @notice Aggregate Junior collateral per pool.
    mapping(PoolId => uint256) internal _juniorCollateral;

    /// @notice Per-LP Junior collateral.
    mapping(PoolId => mapping(address => uint256)) internal _juniorCollateralByOwner;

    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------

    modifier onlyHook() {
        if (msg.sender != hook) revert NotHook();
        _;
    }

    // ---------------------------------------------------------------------
    // Init
    // ---------------------------------------------------------------------

    /// @notice Wire the reserve to its TrancheShieldHook. The reserve is deployed first
    ///         (since the hook constructor takes the reserve address), so this setter
    ///         closes the back-reference one-shot.
    function setHook(address _hook) external {
        if (hook != address(0)) revert HookAlreadySet();
        if (_hook == address(0)) revert ZeroAddress();
        hook = _hook;
    }

    // ---------------------------------------------------------------------
    // Premium routing & compensation payout
    // ---------------------------------------------------------------------

    /// @inheritdoc IProtectionReserve
    function routePremium(PoolId poolId, Currency currency, uint256 amount) external override onlyHook {
        // The hook is expected to have transferred `amount` of `currency` to this
        // contract immediately before this call. We only update bookkeeping here.
        _reserveBalance[poolId][currency] += amount;
        emit PremiumRouted(poolId, currency, amount);
        _emitReserveRatioUpdated(poolId);
    }

    /// @inheritdoc IProtectionReserve
    function payCompensation(PoolId poolId, address recipient, Currency currency, uint256 amount)
        external
        override
        onlyHook
    {
        if (recipient == address(0)) revert ZeroAddress();
        uint256 balance = _reserveBalance[poolId][currency];
        if (balance < amount) revert InsufficientReserve();

        unchecked {
            _reserveBalance[poolId][currency] = balance - amount;
        }
        currency.transfer(recipient, amount);

        emit CompensationPaid(poolId, recipient, currency, amount);
        _emitReserveRatioUpdated(poolId);
    }

    // ---------------------------------------------------------------------
    // Liability / collateral bookkeeping
    // ---------------------------------------------------------------------

    /// @inheritdoc IProtectionReserve
    function increaseSeniorLiability(PoolId poolId, address owner, uint256 amount) external override onlyHook {
        _seniorLiability[poolId] += amount;
        _seniorLiabilityByOwner[poolId][owner] += amount;
        emit SeniorLiabilityIncreased(poolId, owner, amount, _seniorLiability[poolId]);
        _emitReserveRatioUpdated(poolId);
    }

    /// @inheritdoc IProtectionReserve
    function decreaseSeniorLiability(PoolId poolId, address owner, uint256 amount) external override onlyHook {
        uint256 ownerLiability = _seniorLiabilityByOwner[poolId][owner];
        if (ownerLiability < amount) revert LiabilityUnderflow();

        unchecked {
            _seniorLiabilityByOwner[poolId][owner] = ownerLiability - amount;
            _seniorLiability[poolId] -= amount;
        }
        emit SeniorLiabilityDecreased(poolId, owner, amount, _seniorLiability[poolId]);
        _emitReserveRatioUpdated(poolId);
    }

    /// @inheritdoc IProtectionReserve
    function increaseJuniorCollateral(PoolId poolId, address owner, uint256 amount) external override onlyHook {
        _juniorCollateral[poolId] += amount;
        _juniorCollateralByOwner[poolId][owner] += amount;
        emit JuniorCollateralIncreased(poolId, owner, amount, _juniorCollateral[poolId]);
    }

    /// @inheritdoc IProtectionReserve
    function decreaseJuniorCollateral(PoolId poolId, address owner, uint256 amount) external override onlyHook {
        uint256 ownerCollateral = _juniorCollateralByOwner[poolId][owner];
        if (ownerCollateral < amount) revert CollateralUnderflow();

        unchecked {
            _juniorCollateralByOwner[poolId][owner] = ownerCollateral - amount;
            _juniorCollateral[poolId] -= amount;
        }
        emit JuniorCollateralDecreased(poolId, owner, amount, _juniorCollateral[poolId]);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    /// @inheritdoc IProtectionReserve
    function getReserveBalance(PoolId poolId, Currency currency) external view override returns (uint256) {
        return _reserveBalance[poolId][currency];
    }

    /// @inheritdoc IProtectionReserve
    function getSeniorLiability(PoolId poolId) external view override returns (uint256) {
        return _seniorLiability[poolId];
    }

    /// @inheritdoc IProtectionReserve
    function getJuniorCollateral(PoolId poolId) external view override returns (uint256) {
        return _juniorCollateral[poolId];
    }

    /// @inheritdoc IProtectionReserve
    function getReserveRatioBps(PoolId poolId) external view override returns (uint256) {
        return _ratioBps(poolId);
    }

    /// @notice Per-LP Senior liability accessor — useful for the frontend's risk panel.
    function getSeniorLiabilityOf(PoolId poolId, address owner) external view returns (uint256) {
        return _seniorLiabilityByOwner[poolId][owner];
    }

    /// @notice Per-LP Junior collateral accessor.
    function getJuniorCollateralOf(PoolId poolId, address owner) external view returns (uint256) {
        return _juniorCollateralByOwner[poolId][owner];
    }

    // ---------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------

    /// @dev Emits the canonical `ReserveRatioUpdated` event consumed by the Reactive RSC.
    ///      Phase 2 emits a Currency-agnostic ratio using just the Senior-liability
    ///      accumulator; Phase 3 will weight the reserve balance across both pool
    ///      currencies into a unified token1-equivalent figure.
    function _emitReserveRatioUpdated(PoolId poolId) internal {
        emit ReserveRatioUpdated(poolId, 0 /* reserveBalanceToken1Equivalent — Phase 3 */, _seniorLiability[poolId], _ratioBps(poolId));
    }

    function _ratioBps(PoolId poolId) internal view returns (uint256) {
        uint256 liability = _seniorLiability[poolId];
        if (liability == 0) return type(uint256).max; // see interface: "no obligations → trivially solvent"
        // Phase 2 returns 0 until a token1-equivalent reserve figure exists.
        // Real ratio = reserve * 10_000 / liability lands in Phase 3.
        return 0;
    }
}
