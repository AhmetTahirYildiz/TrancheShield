// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";

import {ITrancheShieldHook} from "../src/interfaces/ITrancheShieldHook.sol";

/// @notice Seeds a live TrancheShield pool on Unichain Sepolia and generates volatility
///         so the Reactive controller observes SwapRiskObserved events and escalates the
///         risk mode via a cross-chain callback.
///
/// Steps: deploy 2 mock ERC20s → init dynamic-fee pool with the hook → add deep Junior
///        liquidity → run alternating large swaps to swing the tick.
///
/// Usage (set HOOK_ADDRESS in .env first):
///   forge script script/SeedPool.s.sol:SeedPool \
///     --rpc-url $UNICHAIN_SEPOLIA_RPC --private-key $DEPLOYER_PRIVATE_KEY --broadcast
contract SeedPool is Script {
    address constant POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    address constant MODIFY_ROUTER = 0x5fa728C0A5cfd51BEe4B060773f50554c0C8A7AB;
    address constant SWAP_ROUTER = 0x9140a78c1A137c7fF1c151EC8231272aF78a99A4;

    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint160 constant MIN_SQRT_PRICE_LIMIT = 4295128740;
    uint160 constant MAX_SQRT_PRICE_LIMIT = 1461446703485210103287273052203988822378723970341;

    int24 constant TICK_LOWER = -120000;
    int24 constant TICK_UPPER = 120000;

    function run() external {
        address hookAddr = vm.envAddress("HOOK_ADDRESS");

        IPoolManager manager = IPoolManager(POOL_MANAGER);
        PoolModifyLiquidityTest modifyRouter = PoolModifyLiquidityTest(MODIFY_ROUTER);
        PoolSwapTest swapRouter = PoolSwapTest(SWAP_ROUTER);

        vm.startBroadcast();

        // 1. Two mock tokens, sorted so currency0 < currency1.
        MockERC20 tokenA = new MockERC20("TrancheShield Test A", "TSA", 18);
        MockERC20 tokenB = new MockERC20("TrancheShield Test B", "TSB", 18);
        (MockERC20 token0, MockERC20 token1) =
            address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);

        token0.mint(msg.sender, 1e27);
        token1.mint(msg.sender, 1e27);
        token0.approve(MODIFY_ROUTER, type(uint256).max);
        token1.approve(MODIFY_ROUTER, type(uint256).max);
        token0.approve(SWAP_ROUTER, type(uint256).max);
        token1.approve(SWAP_ROUTER, type(uint256).max);

        // 2. Dynamic-fee pool with the hook.
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(hookAddr)
        });
        manager.initialize(key, SQRT_PRICE_1_1);

        // 3. Deep Junior liquidity (no Senior liability → isolates the volatility path).
        modifyRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams(TICK_LOWER, TICK_UPPER, int256(50e18), bytes32(0)),
            abi.encode(ITrancheShieldHook.Tranche.JUNIOR, msg.sender)
        );

        // 4. Alternating large swaps to swing the tick and feed the Welford window.
        for (uint256 i = 0; i < 8; i++) {
            bool zeroForOne = i % 2 == 0;
            swapRouter.swap(
                key,
                SwapParams({
                    zeroForOne: zeroForOne,
                    amountSpecified: -int256(3e18),
                    sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE_LIMIT : MAX_SQRT_PRICE_LIMIT
                }),
                PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
                "" // swap hooks ignore hookData
            );
        }

        vm.stopBroadcast();

        PoolId poolId = key.toId();
        console2.log("--- Seeded TrancheShield pool (Unichain Sepolia) ---");
        console2.log("token0:", address(token0));
        console2.log("token1:", address(token1));
        console2.log("hook:  ", hookAddr);
        console2.log("poolId:");
        console2.logBytes32(PoolId.unwrap(poolId));
        console2.log("Ran 8 alternating swaps. Watch Reactscan for react()+Callback,");
        console2.log("then read hook.getPoolRiskState(poolId) for the updated mode/fee.");
    }
}
