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
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";

import {ITrancheShieldHook} from "../src/interfaces/ITrancheShieldHook.sol";

/// @notice Seeds a FRESH interactive demo pool on the live hook and leaves it in LOW.
///         Unlike SeedPool, it runs NO swaps — the frontend drives volatility live so
///         judges can watch the pool flip LOW -> CRISIS via the cross-chain RSC callback.
///
/// Adds only deep Junior liquidity: a first-loss buffer + something for browser swaps to
/// trade against. The frontend mints these same MockERC20s to the connected wallet (their
/// `mint` is public) so any funded wallet can deposit Senior and swap.
///
/// Usage (HOOK_ADDRESS in .env):
///   forge script script/SeedInteractivePool.s.sol:SeedInteractivePool \
///     --rpc-url $UNICHAIN_SEPOLIA_RPC --private-key $DEPLOYER_PRIVATE_KEY --broadcast -vv
contract SeedInteractivePool is Script {
    address constant POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    address constant MODIFY_ROUTER = 0x5fa728C0A5cfd51BEe4B060773f50554c0C8A7AB;

    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    int24 constant TICK_LOWER = -120000;
    int24 constant TICK_UPPER = 120000;
    int256 constant JUNIOR_LIQUIDITY = 120e18;

    function run() external {
        address hookAddr = vm.envAddress("HOOK_ADDRESS");
        IPoolManager manager = IPoolManager(POOL_MANAGER);
        PoolModifyLiquidityTest modifyRouter = PoolModifyLiquidityTest(MODIFY_ROUTER);
        address me = msg.sender;

        vm.startBroadcast();

        MockERC20 tokenA = new MockERC20("TrancheShield Interactive A", "TSIA", 18);
        MockERC20 tokenB = new MockERC20("TrancheShield Interactive B", "TSIB", 18);
        (MockERC20 token0, MockERC20 token1) =
            address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);

        token0.mint(me, 1e27);
        token1.mint(me, 1e27);
        token0.approve(MODIFY_ROUTER, type(uint256).max);
        token1.approve(MODIFY_ROUTER, type(uint256).max);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(hookAddr)
        });
        manager.initialize(key, SQRT_PRICE_1_1);

        modifyRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams(TICK_LOWER, TICK_UPPER, JUNIOR_LIQUIDITY, bytes32(0)),
            abi.encode(ITrancheShieldHook.Tranche.JUNIOR, me)
        );

        vm.stopBroadcast();

        PoolId poolId = key.toId();
        console2.log("=== Interactive pool seeded (LOW, no swaps) ===");
        console2.log("token0:", address(token0));
        console2.log("token1:", address(token1));
        console2.log("hook:  ", hookAddr);
        console2.log("poolId:");
        console2.logBytes32(PoolId.unwrap(poolId));
        console2.log("Pool is LOW + Senior-deposits-open. Drive swaps from the frontend");
        console2.log("to flip it to CRISIS via the cross-chain RSC callback.");
    }
}
