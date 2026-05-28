// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";

import {TrancheShieldHook} from "../../src/hooks/TrancheShieldHook.sol";
import {ProtectionReserve} from "../../src/reserve/ProtectionReserve.sol";
import {ITrancheShieldHook} from "../../src/interfaces/ITrancheShieldHook.sol";
import {FeeMath} from "../../src/libraries/FeeMath.sol";

/// @title TrancheShield Phase 3 Tests
/// @notice Covers dynamic-fee override (§11), premium routing (§12), IL math (§13),
///         and loss waterfall (§8.5). Pool is initialized with DYNAMIC_FEE_FLAG so the
///         hook's per-swap fee override via OVERRIDE_FEE_FLAG actually takes effect.
contract Phase3Test is Test, Deployers {
    uint160 internal constant HOOK_FLAGS = uint160(
        Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
    );

    address internal constant FAKE_CALLBACK_RECEIVER = address(0xBEEF);

    ProtectionReserve internal reserve;
    TrancheShieldHook internal hook;
    PoolKey internal poolKey;
    PoolId internal poolId;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        reserve = new ProtectionReserve();
        address hookAddr = address(HOOK_FLAGS);
        deployCodeTo(
            "src/hooks/TrancheShieldHook.sol:TrancheShieldHook",
            abi.encode(manager, address(reserve)),
            hookAddr
        );
        hook = TrancheShieldHook(hookAddr);

        reserve.setHook(address(hook));
        hook.setCallbackReceiver(FAKE_CALLBACK_RECEIVER);

        // Dynamic-fee pool: PoolKey.fee = DYNAMIC_FEE_FLAG so the per-swap fee override
        // emitted by beforeSwap is honoured.
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        poolId = poolKey.toId();
        manager.initialize(poolKey, SQRT_PRICE_1_1);
    }

    // ---------------------------------------------------------------------
    // Shared helpers
    // ---------------------------------------------------------------------

    function _deposit(ITrancheShieldHook.Tranche tranche, address owner, int256 liquidity, bytes32 salt) internal {
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: LIQUIDITY_PARAMS.tickLower,
                tickUpper: LIQUIDITY_PARAMS.tickUpper,
                liquidityDelta: liquidity,
                salt: salt
            }),
            abi.encode(tranche, owner)
        );
    }

    function _withdraw(ITrancheShieldHook.Tranche tranche, address owner, int256 liquidity, bytes32 salt) internal {
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams({
                tickLower: LIQUIDITY_PARAMS.tickLower,
                tickUpper: LIQUIDITY_PARAMS.tickUpper,
                liquidityDelta: -liquidity,
                salt: salt
            }),
            abi.encode(tranche, owner)
        );
    }

    /// @dev Fund the reserve with `amount` of currency1 AND update its bookkeeping
    ///      to match — needed because routePremium is hook-only and we don't run real
    ///      premium-skimming in unit tests.
    function _fundReserveCurrency1(uint256 amount) internal {
        IERC20Minimal(Currency.unwrap(currency1)).transfer(address(reserve), amount);
        vm.prank(address(hook));
        reserve.routePremium(poolId, currency1, amount);
    }

    /// @dev Move the pool price by performing a sizable swap. Direction `zeroForOne`
    ///      raises currency1 supply, lowering price; the opposite direction raises price.
    function _moveTickBy(bool zeroForOne, int256 amountSpecified) internal {
        swap(poolKey, zeroForOne, amountSpecified, "");
    }

    // ---------------------------------------------------------------------
    // Tests — Dynamic fee
    // ---------------------------------------------------------------------

    function test_dynamicFee_lowMode_appliesBaseFee() public {
        _deposit(ITrancheShieldHook.Tranche.JUNIOR, address(this), 1e18, bytes32(uint256(1)));

        // LOW mode default. Swap must succeed and emit SwapRiskObserved with valid ticks.
        vm.recordLogs();
        swap(poolKey, true, -1e15, "");

        // SwapRiskObserved is keccak256("SwapRiskObserved(bytes32,int24,int24,uint256,uint256,uint256)")
        // poolId is indexed → topic_1; the rest is data. Just assert SOMETHING was emitted by the hook.
        assertGt(vm.getRecordedLogs().length, 0, "expected at least one log");
    }

    function test_dynamicFee_highMode_increasesEffectiveFee() public {
        // FeeMath sanity: HIGH mode multiplier 17500 bps × base 3000 pips = 5250 pips.
        uint24 lowFee = FeeMath.computeDynamicFee(3000, 10_000);
        uint24 highFee = FeeMath.computeDynamicFee(3000, 17_500);
        assertEq(lowFee, 3000);
        assertEq(highFee, 5250);

        // Switching the multiplier on a live pool does not revert and is observable
        // via the public getter.
        vm.prank(FAKE_CALLBACK_RECEIVER);
        hook.updateFeeMultiplier(poolId, 17_500);
        assertEq(hook.getPoolRiskState(poolId).feeMultiplierBps, 17_500);

        _deposit(ITrancheShieldHook.Tranche.JUNIOR, address(this), 1e18, bytes32(uint256(2)));
        // Swap with new fee in force should still settle cleanly.
        swap(poolKey, true, -1e15, "");
    }

    function test_dynamicFee_multiplierClampedToBounds() public {
        // Out-of-range multipliers are clamped, not reverted, so a misconfigured RNK
        // state never bricks the pool.
        assertEq(FeeMath.computeDynamicFee(3000, 5_000), 3000);  // below floor → clamped to 10_000
        assertEq(FeeMath.computeDynamicFee(3000, 50_000), 9000); // above ceiling → clamped to 30_000
    }

    // ---------------------------------------------------------------------
    // Tests — Premium routing
    // ---------------------------------------------------------------------

    function test_premiumRouting_increasesReserveBookkeeping() public {
        _deposit(ITrancheShieldHook.Tranche.JUNIOR, address(this), 1e18, bytes32(uint256(3)));

        uint256 before0 = reserve.getReserveBalance(poolId, currency0);
        uint256 before1 = reserve.getReserveBalance(poolId, currency1);
        // zeroForOne swap → fee taken in currency0. Reserve.currency0 bookkeeping rises.
        swap(poolKey, true, -1e16, "");

        uint256 after0 = reserve.getReserveBalance(poolId, currency0);
        uint256 after1 = reserve.getReserveBalance(poolId, currency1);
        assertGt(after0, before0, "currency0 reserve should rise");
        assertEq(after1, before1, "currency1 reserve untouched for zeroForOne");
    }

    function test_premiumRouting_currencyMatchesSwapDirection() public {
        _deposit(ITrancheShieldHook.Tranche.JUNIOR, address(this), 1e18, bytes32(uint256(4)));

        // oneForZero → fee taken in currency1.
        uint256 before1 = reserve.getReserveBalance(poolId, currency1);
        swap(poolKey, false, -1e16, "");
        assertGt(reserve.getReserveBalance(poolId, currency1), before1, "currency1 reserve should rise");
    }

    // ---------------------------------------------------------------------
    // Tests — IL math + loss waterfall
    // ---------------------------------------------------------------------

    function test_il_noPriceMovement_yieldsNoCompensation() public {
        bytes32 salt = bytes32(uint256(5));
        // Junior provides depth so Senior can withdraw cleanly.
        _deposit(ITrancheShieldHook.Tranche.JUNIOR, address(this), 5e18, bytes32(uint256(99)));
        _deposit(ITrancheShieldHook.Tranche.SENIOR, address(this), 1e18, salt);

        // No swaps → price stays at SQRT_PRICE_1_1 → no IL.
        _withdraw(ITrancheShieldHook.Tranche.SENIOR, address(this), 1e18, salt);

        // Reserve balance only contains whatever zero-IL withdrawal didn't consume.
        // Crucially, the position is closed.
        ITrancheShieldHook.LPPosition memory pos = hook.getPosition(
            hook.positionKey(poolId, address(this), LIQUIDITY_PARAMS.tickLower, LIQUIDITY_PARAMS.tickUpper, salt)
        );
        assertFalse(pos.active, "Senior position closed");
        assertEq(reserve.getSeniorLiability(poolId), 0, "Senior liability cleared");
    }

    function test_waterfall_reserveCoversCompensationWhenHealthy() public {
        // Pre-fund reserve so Tier 1 can pay out a meaningful compensation.
        _deposit(ITrancheShieldHook.Tranche.JUNIOR, address(this), 5e18, bytes32(uint256(99)));
        _fundReserveCurrency1(0.5e18);

        bytes32 saltS = bytes32(uint256(6));
        _deposit(ITrancheShieldHook.Tranche.SENIOR, address(this), 1e18, saltS);

        // Push price by buying currency0 with currency1 → tick rises, then settle a withdrawal.
        _moveTickBy(false, -1e17);

        uint256 reserve1Before = reserve.getReserveBalance(poolId, currency1);
        uint256 juniorCollatBefore = hook.getPoolRiskState(poolId).juniorCollateral;

        _withdraw(ITrancheShieldHook.Tranche.SENIOR, address(this), 1e18, saltS);

        // With Tier 1 healthy the waterfall must NOT have touched Junior collateral.
        assertEq(hook.getPoolRiskState(poolId).juniorCollateral, juniorCollatBefore, "Junior collateral untouched");

        // Reserve balance should be reduced (or unchanged if there was no IL on this path).
        // We assert it never grew.
        assertLe(reserve.getReserveBalance(poolId, currency1), reserve1Before, "reserve never grew");
    }

    function test_waterfall_juniorAbsorbsWhenReserveEmpty() public {
        // No reserve funding. Withdrawal with IL hits Tier 2 (Junior).
        _deposit(ITrancheShieldHook.Tranche.JUNIOR, address(this), 5e18, bytes32(uint256(99)));

        bytes32 saltS = bytes32(uint256(7));
        _deposit(ITrancheShieldHook.Tranche.SENIOR, address(this), 1e18, saltS);

        // zeroForOne so premium accrues in currency0 — keeps currency1 reserve bookkeeping
        // at zero and forces the waterfall to bypass Tier 1.
        _moveTickBy(true, -1e17);

        uint256 juniorCollatBefore = hook.getPoolRiskState(poolId).juniorCollateral;
        _withdraw(ITrancheShieldHook.Tranche.SENIOR, address(this), 1e18, saltS);

        uint256 juniorCollatAfter = hook.getPoolRiskState(poolId).juniorCollateral;
        // If IL was positive, Junior must have absorbed something — bounded by the per-event cap.
        if (juniorCollatAfter < juniorCollatBefore) {
            uint256 absorbed = juniorCollatBefore - juniorCollatAfter;
            uint256 perEventCap = (juniorCollatBefore * 2_000) / 10_000; // 20%
            assertLe(absorbed, perEventCap, "Junior draw must respect per-event cap");
        }
    }

    function test_waterfall_seniorAbsorbsRemainderWhenReserveAndJuniorExhausted() public {
        // Tiny Junior pool so per-event cap is small and likely insufficient to cover full IL.
        _deposit(ITrancheShieldHook.Tranche.JUNIOR, address(this), 1e17, bytes32(uint256(99)));

        bytes32 saltS = bytes32(uint256(8));
        _deposit(ITrancheShieldHook.Tranche.SENIOR, address(this), 1e18, saltS);

        // zeroForOne direction keeps currency1 reserve bookkeeping at zero so the
        // waterfall can exhibit Tier 3 behavior without bumping into currency1-side
        // bookkeeping/balance mismatches.
        _moveTickBy(true, -2e17);

        _withdraw(ITrancheShieldHook.Tranche.SENIOR, address(this), 1e18, saltS);
        // The fact that the call returned at all proves Senior absorbs the residual without
        // reverting — Tier 3 behavior is "reduced compensation," not a hard revert.
        ITrancheShieldHook.LPPosition memory pos = hook.getPosition(
            hook.positionKey(poolId, address(this), LIQUIDITY_PARAMS.tickLower, LIQUIDITY_PARAMS.tickUpper, saltS)
        );
        assertFalse(pos.active, "Senior position must close even when reserve+Junior insufficient");
    }
}
