// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {V4Quoter} from "v4-periphery/lens/V4Quoter.sol";
import {IV4Quoter} from "v4-periphery/interfaces/IV4Quoter.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";

/// @notice Proves the TrancheShieldHook pool is quotable by a standard Uniswap v4 router/lens:
///         deploys the official `V4Quoter` against the live PoolManager and quotes an exact-input
///         swap on the live demo pool. The hook only sets a dynamic fee in `beforeSwap` and returns
///         no custom swap delta, so the quote runs through the hook exactly like a normal swap.
///
/// Validate (no broadcast, forks live state):
///   forge script script/QuoteCheck.s.sol:QuoteCheck --rpc-url $UNICHAIN_SEPOLIA_RPC -vv
/// Persist the Quoter on-chain (so the frontend can quote live):
///   forge script script/QuoteCheck.s.sol:QuoteCheck --rpc-url $UNICHAIN_SEPOLIA_RPC \
///     --private-key $DEPLOYER_PRIVATE_KEY --broadcast -vv
contract QuoteCheck is Script {
    address constant POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    address constant HOOK = 0x696d7E04C2637630FEC303628BF774aE57c48Fc0;

    // Live demo pool (Unichain Sepolia) — see docs/deployment.md.
    address constant TOKEN0 = 0x9903fA2E3c3291cfFBde6958676ADC92737a82a0;
    address constant TOKEN1 = 0xb9CC9045d84485E5864B5eF2ECc77931824B89E2;

    function run() external {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(TOKEN0),
            currency1: Currency.wrap(TOKEN1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(HOOK)
        });

        vm.startBroadcast();
        V4Quoter quoter = new V4Quoter(IPoolManager(POOL_MANAGER));
        vm.stopBroadcast();

        uint128 amountIn = 1e18;
        (uint256 amountOut, uint256 gasEstimate) = quoter.quoteExactInputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: key,
                zeroForOne: true,
                exactAmount: amountIn,
                hookData: ""
            })
        );

        console2.log("=== V4Quoter routability proof (Unichain Sepolia) ===");
        console2.log("V4Quoter:", address(quoter));
        console2.log("poolId:");
        console2.logBytes32(PoolId.unwrap(key.toId()));
        console2.log("quote: exactIn", uint256(amountIn), "token0 (zeroForOne)");
        console2.log("amountOut token1:", amountOut);
        console2.log("gasEstimate:    ", gasEstimate);
    }
}
