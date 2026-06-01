// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";

import {IReactive} from "@reactive-lib/interfaces/IReactive.sol";

import {TrancheShieldHook} from "../../src/hooks/TrancheShieldHook.sol";
import {ProtectionReserve} from "../../src/reserve/ProtectionReserve.sol";
import {CallbackReceiver} from "../../src/reactive/CallbackReceiver.sol";
import {ReactiveRiskController} from "../../src/reactive/ReactiveRiskController.sol";
import {ITrancheShieldHook} from "../../src/interfaces/ITrancheShieldHook.sol";

/// @title Phase 4 Reactive integration tests
/// @notice Two halves:
///         (1) CallbackReceiver — rvmId auth, proxy auth, bounds enforcement, and that
///             accepted callbacks flow through to the hook's risk state.
///         (2) ReactiveRiskController.react() — exercised in isolation with mocked
///             LogRecords. In a Foundry test there is no system contract at 0xfffFfF, so
///             AbstractReactive.detectVm() sets vm=true: `vmOnly` passes and the
///             constructor skips subscribe().
contract ReactiveCallbacksTest is Test, Deployers {
    uint160 internal constant HOOK_FLAGS = uint160(
        Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
    );

    // Real canonical topic_0 hashes (cast keccak of the event signatures).
    uint256 internal constant SWAP_TOPIC0 =
        uint256(0x9c2482833c741d11c91227f8777c59c5f0d8030dc7c38cf429a7847f6329d9b6);
    uint256 internal constant WITHDRAW_TOPIC0 =
        uint256(0x89691e6ba9d3b74b11b685b0e2b76aa2f11ad1dd5ba389acb7831608fe25ec04);
    uint256 internal constant RESERVE_TOPIC0 =
        uint256(0xa9f0f960579c81a9d006a05f0c56e58020e1d1f4fb2ad890a2c557f708c6cfee);

    address internal constant CALLBACK_PROXY = address(0xCAFE);

    ProtectionReserve internal reserve;
    TrancheShieldHook internal hook;
    CallbackReceiver internal cr;
    ReactiveRiskController internal rsc;

    PoolKey internal poolKey;
    PoolId internal poolId;
    bytes32 internal poolIdBytes;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        reserve = new ProtectionReserve();
        address hookAddr = address(HOOK_FLAGS);
        deployCodeTo(
            "src/hooks/TrancheShieldHook.sol:TrancheShieldHook",
            abi.encode(manager, address(reserve), address(this)),
            hookAddr
        );
        hook = TrancheShieldHook(hookAddr);
        reserve.setHook(address(hook));

        // CallbackReceiver: rvm_id = msg.sender (this test contract); proxy authorized.
        cr = new CallbackReceiver(CALLBACK_PROXY, address(hook));
        hook.setCallbackReceiver(address(cr));

        // Controller: in-test vm==true, so subscribe() is skipped. cron topic 0 = disabled.
        rsc = new ReactiveRiskController(
            address(hook), address(reserve), address(cr), SWAP_TOPIC0, RESERVE_TOPIC0, WITHDRAW_TOPIC0, 0
        );

        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        poolId = poolKey.toId();
        manager.initialize(poolKey, SQRT_PRICE_1_1);
        poolIdBytes = PoolId.unwrap(poolId);

        // Touch the pool so risk state has defaults to mutate.
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            LIQUIDITY_PARAMS,
            abi.encode(ITrancheShieldHook.Tranche.JUNIOR, address(this))
        );

        vm.roll(100); // clear the rate-limit window for controller tests
    }

    // ---------------------------------------------------------------------
    // CallbackReceiver — auth + bounds
    // ---------------------------------------------------------------------

    function test_setRiskMode_acceptsAuthorizedRvmId() public {
        vm.prank(CALLBACK_PROXY);
        cr.setRiskMode(address(this), poolIdBytes, uint8(ITrancheShieldHook.RiskMode.HIGH));
        assertEq(uint8(hook.getPoolRiskState(poolId).mode), uint8(ITrancheShieldHook.RiskMode.HIGH));
    }

    function test_setRiskMode_acceptsCorrectRvmIdFromAnySender() public {
        // Design note: the receiver is gated by `rvmIdOnly` only (PROJECT-v2.md §8.4).
        // `authorizedSenderOnly` was removed because the live Reactive callback sender on
        // Unichain Sepolia is not the registered proxy. So a call with the correct rvmId
        // succeeds regardless of msg.sender; the rvmId is the security anchor.
        cr.setRiskMode(address(this), poolIdBytes, uint8(ITrancheShieldHook.RiskMode.HIGH));
        assertEq(uint8(hook.getPoolRiskState(poolId).mode), uint8(ITrancheShieldHook.RiskMode.HIGH));
    }

    function test_setRiskMode_revertsFromWrongRvmId() public {
        vm.prank(CALLBACK_PROXY);
        vm.expectRevert(bytes("Authorized RVM ID only"));
        cr.setRiskMode(address(0xDEAD), poolIdBytes, uint8(ITrancheShieldHook.RiskMode.HIGH));
    }

    function test_setRiskMode_revertsOnInvalidMode() public {
        vm.prank(CALLBACK_PROXY);
        vm.expectRevert(abi.encodeWithSelector(CallbackReceiver.InvalidRiskMode.selector, uint8(4)));
        cr.setRiskMode(address(this), poolIdBytes, 4);
    }

    function test_updateFeeMultiplier_acceptsInBounds() public {
        vm.prank(CALLBACK_PROXY);
        cr.updateFeeMultiplier(address(this), poolIdBytes, 17_500);
        assertEq(hook.getPoolRiskState(poolId).feeMultiplierBps, 17_500);
    }

    function test_updateFeeMultiplier_revertsBelowFloor() public {
        vm.prank(CALLBACK_PROXY);
        vm.expectRevert(abi.encodeWithSelector(CallbackReceiver.FeeMultiplierOutOfBounds.selector, uint256(9_999)));
        cr.updateFeeMultiplier(address(this), poolIdBytes, 9_999);
    }

    function test_updateFeeMultiplier_revertsAboveCeiling() public {
        vm.prank(CALLBACK_PROXY);
        vm.expectRevert(abi.encodeWithSelector(CallbackReceiver.FeeMultiplierOutOfBounds.selector, uint256(30_001)));
        cr.updateFeeMultiplier(address(this), poolIdBytes, 30_001);
    }

    function test_updateCoverageRatio_acceptsAtCeiling() public {
        vm.prank(CALLBACK_PROXY);
        cr.updateCoverageRatio(address(this), poolIdBytes, 5_000);
        assertEq(hook.getPoolRiskState(poolId).coverageRatioBps, 5_000);
    }

    function test_updateCoverageRatio_revertsAboveCeiling() public {
        vm.prank(CALLBACK_PROXY);
        vm.expectRevert(abi.encodeWithSelector(CallbackReceiver.CoverageRatioOutOfBounds.selector, uint256(5_001)));
        cr.updateCoverageRatio(address(this), poolIdBytes, 5_001);
    }

    function test_setSeniorDepositStatus_flowsToHook() public {
        vm.prank(CALLBACK_PROXY);
        cr.setSeniorDepositStatus(address(this), poolIdBytes, false);
        assertFalse(hook.getPoolRiskState(poolId).seniorDepositsEnabled);
    }

    // ---------------------------------------------------------------------
    // ReactiveRiskController.react() — mocked LogRecords
    // ---------------------------------------------------------------------

    function _swapLog(int24 tickBefore, int24 tickAfter) internal view returns (IReactive.LogRecord memory) {
        return IReactive.LogRecord({
            chain_id: 1301,
            _contract: address(hook),
            topic_0: SWAP_TOPIC0,
            topic_1: uint256(poolIdBytes),
            topic_2: 0,
            topic_3: 0,
            data: abi.encode(tickBefore, tickAfter, uint256(1e18), uint256(1e18), block.timestamp),
            block_number: block.number,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });
    }

    function _reserveLog(uint256 ratioBps) internal view returns (IReactive.LogRecord memory) {
        return IReactive.LogRecord({
            chain_id: 1301,
            _contract: address(reserve),
            topic_0: RESERVE_TOPIC0,
            topic_1: uint256(poolIdBytes),
            topic_2: 0,
            topic_3: 0,
            data: abi.encode(uint256(0), uint256(1e18), ratioBps),
            block_number: block.number,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });
    }

    function _withdrawLog(uint256 timestamp) internal view returns (IReactive.LogRecord memory) {
        return IReactive.LogRecord({
            chain_id: 1301,
            _contract: address(hook),
            topic_0: WITHDRAW_TOPIC0,
            topic_1: uint256(poolIdBytes),
            topic_2: uint256(uint160(address(this))),
            topic_3: 0,
            data: abi.encode(uint256(1e18), timestamp),
            block_number: block.number,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });
    }

    function test_react_highVolatility_changesModeAndEmitsCallback() public {
        // Alternate widely-separated ticks to drive variance well past the CRISIS threshold.
        vm.recordLogs();
        for (uint256 i = 0; i < 8; i++) {
            int24 t = i % 2 == 0 ? int24(0) : int24(5000);
            rsc.react(_swapLog(0, t));
        }

        // Mode must have escalated above LOW.
        assertTrue(uint8(rsc.currentRiskMode()) > uint8(ReactiveRiskController.RiskMode.LOW), "mode escalated");

        // At least one Reactive Callback event must have been emitted.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 callbackSig = keccak256("Callback(uint256,address,uint64,bytes)");
        uint256 callbacks;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == callbackSig) callbacks++;
        }
        assertGt(callbacks, 0, "expected at least one cross-chain Callback");
    }

    function test_react_lowVolatility_staysLow() public {
        // Nearly-flat ticks keep variance below the MEDIUM threshold.
        for (uint256 i = 0; i < 6; i++) {
            rsc.react(_swapLog(0, int24(uint24(i % 2))));
        }
        assertEq(uint8(rsc.currentRiskMode()), uint8(ReactiveRiskController.RiskMode.LOW), "stays LOW");
    }

    function test_react_criticalReserve_entersCrisis() public {
        // reserveRatioBps below the critical threshold (7000) → CRISIS + deposits off.
        vm.recordLogs();
        rsc.react(_reserveLog(5_000));

        assertEq(uint8(rsc.currentRiskMode()), uint8(ReactiveRiskController.RiskMode.CRISIS), "entered CRISIS");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 callbackSig = keccak256("Callback(uint256,address,uint64,bytes)");
        uint256 callbacks;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == callbackSig) callbacks++;
        }
        // Expect 3 callbacks: updateCoverageRatio + setRiskMode + setSeniorDepositStatus.
        assertEq(callbacks, 3, "expected 3 crisis callbacks");
    }

    function test_react_bankRun_triggersCrisis() public {
        // Five Senior withdrawals within the bank-run window (default 5).
        vm.recordLogs();
        for (uint256 i = 0; i < 5; i++) {
            rsc.react(_withdrawLog(1_000));
        }
        assertEq(uint8(rsc.currentRiskMode()), uint8(ReactiveRiskController.RiskMode.CRISIS), "bank-run -> CRISIS");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 callbackSig = keccak256("Callback(uint256,address,uint64,bytes)");
        uint256 callbacks;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == callbackSig) callbacks++;
        }
        // setRiskMode + updateCoverageRatio + setSeniorDepositStatus.
        assertEq(callbacks, 3, "expected 3 bank-run callbacks");
    }

    function test_react_belowBankRunThreshold_noCrisis() public {
        for (uint256 i = 0; i < 4; i++) {
            rsc.react(_withdrawLog(1_000));
        }
        assertEq(uint8(rsc.currentRiskMode()), uint8(ReactiveRiskController.RiskMode.LOW), "stays LOW under threshold");
    }
}
