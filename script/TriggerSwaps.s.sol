// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";

/// @notice Runs alternating swaps on an already-seeded pool to generate volatility for a
///         freshly-deployed RSC. Reads TOKEN0/TOKEN1/HOOK_ADDRESS from env.
contract TriggerSwaps is Script {
    address constant SWAP_ROUTER = 0x9140a78c1A137c7fF1c151EC8231272aF78a99A4;
    uint160 constant MIN_SQRT_PRICE_LIMIT = 4295128740;
    uint160 constant MAX_SQRT_PRICE_LIMIT = 1461446703485210103287273052203988822378723970341;

    function run() external {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(vm.envAddress("TOKEN0")),
            currency1: Currency.wrap(vm.envAddress("TOKEN1")),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(vm.envAddress("HOOK_ADDRESS"))
        });

        vm.startBroadcast();
        for (uint256 i = 0; i < 8; i++) {
            bool zeroForOne = i % 2 == 0;
            PoolSwapTest(SWAP_ROUTER).swap(
                key,
                SwapParams({
                    zeroForOne: zeroForOne,
                    amountSpecified: -int256(3e18),
                    sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE_LIMIT : MAX_SQRT_PRICE_LIMIT
                }),
                PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
                ""
            );
        }
        vm.stopBroadcast();
        console2.log("8 alternating swaps done -> SwapRiskObserved emitted for the fresh RSC");
    }
}
