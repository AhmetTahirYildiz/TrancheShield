// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {HelloWorldReactive} from "../../src/playground/HelloWorldReactive.sol";

/// @notice Deploys HelloWorldReactive on Lasna and pre-funds it with lREACT
///         so it can pay the system contract for subscription + callback gas.
///
/// Environment:
///   ORIGIN_CHAIN_ID         (default: 1301, Unichain Sepolia)
///   HELLO_EMITTER           (required) — HelloWorldEmitter address from DeployHello
///   DESTINATION_CHAIN_ID    (default: 1301, Unichain Sepolia)
///   HELLO_RECEIVER          (required) — HelloWorldReceiver address from DeployHello
///   RSC_PREFUND_WEI         (default: 1e18, i.e. 1 lREACT)
///
/// Usage:
///   forge script script/playground/DeployReactive.s.sol \
///     --rpc-url $LASNA_RPC \
///     --private-key $DEPLOYER_PRIVATE_KEY \
///     --broadcast
contract DeployReactive is Script {
    uint256 constant DEFAULT_ORIGIN_CHAIN_ID = 1301;
    uint256 constant DEFAULT_DEST_CHAIN_ID = 1301;
    uint256 constant DEFAULT_PREFUND = 1 ether; // 1 lREACT

    function run() external {
        uint256 originChainId = _envOrDefaultUint("ORIGIN_CHAIN_ID", DEFAULT_ORIGIN_CHAIN_ID);
        address emitterAddr = vm.envAddress("HELLO_EMITTER");
        uint256 destChainId = _envOrDefaultUint("DESTINATION_CHAIN_ID", DEFAULT_DEST_CHAIN_ID);
        address receiverAddr = vm.envAddress("HELLO_RECEIVER");
        uint256 prefund = _envOrDefaultUint("RSC_PREFUND_WEI", DEFAULT_PREFUND);

        vm.startBroadcast();

        HelloWorldReactive rsc = new HelloWorldReactive{value: prefund}(
            originChainId,
            emitterAddr,
            destChainId,
            receiverAddr
        );

        vm.stopBroadcast();

        console2.log("--- Hello World Reactive (Lasna) ---");
        console2.log("RSC:               ", address(rsc));
        console2.log("Origin chain:      ", originChainId);
        console2.log("Watching emitter:  ", emitterAddr);
        console2.log("Destination chain: ", destChainId);
        console2.log("Target receiver:   ", receiverAddr);
        console2.log("RSC balance:       ", address(rsc).balance);
    }

    function _envOrDefaultUint(string memory key, uint256 fallbackVal) internal view returns (uint256) {
        try vm.envUint(key) returns (uint256 v) {
            return v;
        } catch {
            return fallbackVal;
        }
    }
}
