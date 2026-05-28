// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ReactiveRiskController} from "../src/reactive/ReactiveRiskController.sol";

/// @notice Deploys the ReactiveRiskController (RSC) to Reactive Lasna Testnet (5318007).
///
/// ⚠️ DO NOT deploy this with `forge script --broadcast`. The constructor calls
///    `service.subscribe()`, which reads the system contract via the custom precompile at
///    0x64. `forge script` runs a local EVM simulation first, and the local EVM has no
///    0x64 precompile, so the constructor reverts with "Failure". (Learned the hard way in
///    the Phase-1 Hello World playground; see docs/deployment.md.)
///
///    Deploy with `forge create` instead, which sends the tx straight to the RPC:
///
///      forge create src/reactive/ReactiveRiskController.sol:ReactiveRiskController \
///        --rpc-url $LASNA_RPC \
///        --private-key $DEPLOYER_PRIVATE_KEY \
///        --broadcast --legacy --value 5ether \
///        --constructor-args \
///          $HOOK_ADDRESS $RESERVE_ADDRESS $CALLBACK_RECEIVER \
///          0x9c2482833c741d11c91227f8777c59c5f0d8030dc7c38cf429a7847f6329d9b6 \
///          0xa9f0f960579c81a9d006a05f0c56e58020e1d1f4fb2ad890a2c557f708c6cfee \
///          0x89691e6ba9d3b74b11b685b0e2b76aa2f11ad1dd5ba389acb7831608fe25ec04 \
///          0
///
///    The last arg is the Cron topic_0; pass 0 to disable the periodic check (slip-plan
///    fallback #1), or the real Cron topic to enable it.
///
/// This script is kept as executable documentation: running it WITHOUT --broadcast prints
/// the exact constructor args and the canonical event topic_0 hashes, computed live so they
/// can never drift from the actual event signatures.
contract DeployReactiveLasna is Script {
    // keccak256 of the canonical event signatures the RSC subscribes to. PoolId is a
    // user-defined value type over bytes32, so it appears as `bytes32` in the ABI.
    bytes32 constant SWAP_TOPIC0 = keccak256("SwapRiskObserved(bytes32,int24,int24,uint256,uint256,uint256)");
    bytes32 constant RESERVE_TOPIC0 = keccak256("ReserveRatioUpdated(bytes32,uint256,uint256,uint256)");
    bytes32 constant WITHDRAW_TOPIC0 = keccak256("SeniorWithdrawalRequested(bytes32,address,uint256,uint256)");

    function run() external view {
        address hook = vm.envAddress("HOOK_ADDRESS");
        address reserve = vm.envAddress("RESERVE_ADDRESS");
        address callbackReceiver = vm.envAddress("CALLBACK_RECEIVER");
        uint256 cronTopic0 = _envOrZero("CRON_TOPIC0");

        console2.log("--- ReactiveRiskController constructor args (deploy with forge create) ---");
        console2.log("hook:            ", hook);
        console2.log("reserve:         ", reserve);
        console2.log("callbackReceiver:", callbackReceiver);
        console2.log("swapTopic0:");
        console2.logBytes32(SWAP_TOPIC0);
        console2.log("reserveTopic0:");
        console2.logBytes32(RESERVE_TOPIC0);
        console2.log("withdrawTopic0:");
        console2.logBytes32(WITHDRAW_TOPIC0);
        console2.log("cronTopic0:", cronTopic0);

        // Reference the type so the controller is compiled and bytecode is available to
        // `forge create`. (Avoids an unused-import lint and proves the artifact exists.)
        console2.log("creationCode size:", type(ReactiveRiskController).creationCode.length);
    }

    function _envOrZero(string memory key) internal view returns (uint256) {
        try vm.envUint(key) returns (uint256 v) {
            return v;
        } catch {
            return 0;
        }
    }
}
