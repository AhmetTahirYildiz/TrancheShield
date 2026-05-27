// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {HelloWorldEmitter} from "../../src/playground/HelloWorldEmitter.sol";
import {HelloWorldReceiver} from "../../src/playground/HelloWorldReceiver.sol";

/// @notice Deploys the Hello World pair on Unichain Sepolia.
///         Pre-funds the Receiver so it can pay back the Callback Proxy.
///
/// Usage:
///   forge script script/playground/DeployHello.s.sol \
///     --rpc-url $UNICHAIN_SEPOLIA_RPC \
///     --private-key $DEPLOYER_PRIVATE_KEY \
///     --broadcast
contract DeployHello is Script {
    /// @dev Callback Proxy on Unichain Sepolia (chain 1301). See §22 of the spec.
    address constant DEFAULT_CALLBACK_PROXY = 0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4;

    /// @dev Pre-fund the receiver with this much native ETH so it can settle
    ///      the Callback Proxy's debt invoice on first roundtrip.
    uint256 constant RECEIVER_PREFUND = 0.05 ether;

    function run() external {
        address callbackProxy = _envOrDefault("CALLBACK_PROXY", DEFAULT_CALLBACK_PROXY);

        vm.startBroadcast();

        HelloWorldEmitter emitter = new HelloWorldEmitter();
        HelloWorldReceiver receiver = new HelloWorldReceiver{value: RECEIVER_PREFUND}(callbackProxy);

        vm.stopBroadcast();

        console2.log("--- Hello World (Unichain Sepolia) ---");
        console2.log("CallbackProxy:", callbackProxy);
        console2.log("Emitter:      ", address(emitter));
        console2.log("Receiver:     ", address(receiver));
        console2.log("Receiver bal: ", address(receiver).balance);
    }

    function _envOrDefault(string memory key, address fallbackAddr) internal view returns (address) {
        try vm.envAddress(key) returns (address v) {
            return v;
        } catch {
            return fallbackAddr;
        }
    }
}
