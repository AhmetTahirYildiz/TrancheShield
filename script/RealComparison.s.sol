// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";

import {TrancheShieldHook} from "../src/hooks/TrancheShieldHook.sol";
import {ITrancheShieldHook} from "../src/interfaces/ITrancheShieldHook.sol";

/// @notice Runs a REAL end-to-end IL-protection scenario on a fresh pool of the live
///         TrancheShieldHook, so the frontend's comparison view can read genuine
///         on-chain `PositionClosed(ilShortfall, compensation)` data instead of a model.
///
/// Flow on a fresh dynamic-fee pool (default risk state: LOW, coverage 50%, Senior open):
///   1. Junior LP deposits deep liquidity → becomes the first-loss buffer (juniorCollateral).
///   2. Senior LP deposits a smaller full-range position.
///   3. One-directional swaps push the price → the Senior position realizes impermanent loss.
///   4. The Senior LP withdraws → the hook computes IL, applies 50% coverage, and draws the
///      compensation from the Junior tranche (Tier 2 of the waterfall). Emits PositionClosed.
///
/// The reserve is intentionally left empty so compensation flows from the Junior tranche
/// (bookkeeping decrement, no token transfer needed) — this is the honest, fundable path on
/// the frozen MVP contracts and directly demonstrates Junior-backs-Senior first-loss capital.
///
/// Usage (HOOK_ADDRESS in .env):
///   forge script script/RealComparison.s.sol:RealComparison \
///     --rpc-url $UNICHAIN_SEPOLIA_RPC --private-key $DEPLOYER_PRIVATE_KEY --broadcast
contract RealComparison is Script {
    using StateLibrary for IPoolManager;

    address constant POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    address constant MODIFY_ROUTER = 0x5fa728C0A5cfd51BEe4B060773f50554c0C8A7AB;
    address constant SWAP_ROUTER = 0x9140a78c1A137c7fF1c151EC8231272aF78a99A4;

    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint160 constant MIN_SQRT_PRICE_LIMIT = 4295128740;
    uint160 constant MAX_SQRT_PRICE_LIMIT = 1461446703485210103287273052203988822378723970341;

    int24 constant TICK_LOWER = -120000;
    int24 constant TICK_UPPER = 120000;

    int256 constant JUNIOR_LIQUIDITY = 80e18;
    int256 constant SENIOR_LIQUIDITY = 12e18;
    bytes32 constant JUNIOR_SALT = bytes32(0);
    bytes32 constant SENIOR_SALT = bytes32(uint256(1));

    uint256 constant SWAP_COUNT = 7;
    int256 constant SWAP_SIZE = 14e18;

    // PositionClosed(bytes32 indexed,address indexed,bytes32 indexed,uint256,uint256)
    bytes32 constant POSITION_CLOSED_TOPIC =
        keccak256("PositionClosed(bytes32,address,bytes32,uint256,uint256)");

    function run() external {
        address hookAddr = vm.envAddress("HOOK_ADDRESS");
        TrancheShieldHook hook = TrancheShieldHook(hookAddr);

        IPoolManager manager = IPoolManager(POOL_MANAGER);
        PoolModifyLiquidityTest modifyRouter = PoolModifyLiquidityTest(MODIFY_ROUTER);
        PoolSwapTest swapRouter = PoolSwapTest(SWAP_ROUTER);

        address me = msg.sender;

        vm.startBroadcast();

        // 1. Fresh mock tokens, sorted so currency0 < currency1.
        MockERC20 tokenA = new MockERC20("TrancheShield Demo A", "TSDA", 18);
        MockERC20 tokenB = new MockERC20("TrancheShield Demo B", "TSDB", 18);
        (MockERC20 token0, MockERC20 token1) =
            address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);

        token0.mint(me, 1e27);
        token1.mint(me, 1e27);
        token0.approve(MODIFY_ROUTER, type(uint256).max);
        token1.approve(MODIFY_ROUTER, type(uint256).max);
        token0.approve(SWAP_ROUTER, type(uint256).max);
        token1.approve(SWAP_ROUTER, type(uint256).max);

        // 2. Fresh dynamic-fee pool (default risk state on first touch).
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(hookAddr)
        });
        manager.initialize(key, SQRT_PRICE_1_1);

        // 3. Junior first-loss buffer.
        modifyRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams(TICK_LOWER, TICK_UPPER, JUNIOR_LIQUIDITY, JUNIOR_SALT),
            abi.encode(ITrancheShieldHook.Tranche.JUNIOR, me)
        );

        // 4. Senior position (the one that will be IL-protected).
        modifyRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams(TICK_LOWER, TICK_UPPER, SENIOR_LIQUIDITY, SENIOR_SALT),
            abi.encode(ITrancheShieldHook.Tranche.SENIOR, me)
        );

        (, int24 entryTick,,) = manager.getSlot0(key.toId());

        // 5. One-directional swaps to move the price and realize IL.
        for (uint256 i = 0; i < SWAP_COUNT; i++) {
            swapRouter.swap(
                key,
                SwapParams({
                    zeroForOne: true,
                    amountSpecified: -SWAP_SIZE,
                    sqrtPriceLimitX96: MIN_SQRT_PRICE_LIMIT
                }),
                PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
                ""
            );
        }

        (, int24 exitTick,,) = manager.getSlot0(key.toId());

        // 6. Withdraw the Senior position — emits PositionClosed(ilShortfall, compensation).
        vm.recordLogs();
        modifyRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams(TICK_LOWER, TICK_UPPER, -SENIOR_LIQUIDITY, SENIOR_SALT),
            abi.encode(ITrancheShieldHook.Tranche.SENIOR, me)
        );
        (uint256 ilShortfall, uint256 compensation) = _readPositionClosed(hookAddr);

        vm.stopBroadcast();

        PoolId poolId = key.toId();
        bytes32 seniorKey = hook.positionKey(poolId, me, TICK_LOWER, TICK_UPPER, SENIOR_SALT);

        console2.log("=== RealComparison scenario (Unichain Sepolia) ===");
        console2.log("token0:", address(token0));
        console2.log("token1:", address(token1));
        console2.log("hook:  ", hookAddr);
        console2.log("owner: ", me);
        console2.log("poolId:");
        console2.logBytes32(PoolId.unwrap(poolId));
        console2.log("seniorPositionKey:");
        console2.logBytes32(seniorKey);
        console2.log("entryTick:", entryTick);
        console2.log("exitTick: ", exitTick);
        console2.log("--- real PositionClosed (token1 wei) ---");
        console2.log("ilShortfall: ", ilShortfall);
        console2.log("compensation:", compensation);
        if (ilShortfall > 0) {
            console2.log("recovery bps:", (compensation * 10_000) / ilShortfall);
        }
    }

    function _readPositionClosed(address hookAddr)
        internal
        returns (uint256 ilShortfall, uint256 compensation)
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == hookAddr && logs[i].topics[0] == POSITION_CLOSED_TOPIC) {
                (ilShortfall, compensation) = abi.decode(logs[i].data, (uint256, uint256));
                return (ilShortfall, compensation);
            }
        }
    }
}
