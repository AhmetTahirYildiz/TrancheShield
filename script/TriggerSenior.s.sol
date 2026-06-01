// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";

import {ITrancheShieldHook} from "../src/interfaces/ITrancheShieldHook.sol";

/// @notice One-off: add a Senior position to the existing seeded pool. This emits
///         ReserveRatioUpdated (with seniorLiability > 0 → ratio band "critical" in the
///         Phase-3 placeholder), which the RSC turns into a fresh updateCoverageRatio
///         callback. Used to demonstrate a successful cross-chain roundtrip after the
///         receiver was whitelisted by its (failed) first callback.
contract TriggerSenior is Script {
    address constant MODIFY_ROUTER = 0x5fa728C0A5cfd51BEe4B060773f50554c0C8A7AB;

    function run() external {
        address token0 = vm.envAddress("TOKEN0");
        address token1 = vm.envAddress("TOKEN1");
        address hookAddr = vm.envAddress("HOOK_ADDRESS");

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(hookAddr)
        });

        vm.startBroadcast();
        PoolModifyLiquidityTest(MODIFY_ROUTER).modifyLiquidity(
            key,
            ModifyLiquidityParams(-120000, 120000, int256(5e18), bytes32(uint256(0x5e))),
            abi.encode(ITrancheShieldHook.Tranche.SENIOR, msg.sender)
        );
        vm.stopBroadcast();

        console2.log("Senior deposit done -> ReserveRatioUpdated emitted -> RSC should emit updateCoverageRatio callback");
    }
}
