// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {HelloWorldEmitter} from "../../src/playground/HelloWorldEmitter.sol";
import {HelloWorldReceiver} from "../../src/playground/HelloWorldReceiver.sol";

/// @notice Trigger the Hello World roundtrip from the deployer EOA.
///
/// Environment:
///   HELLO_EMITTER     (required)  — emitter address on Unichain Sepolia
///   HELLO_RECEIVER    (optional)  — receiver address, logged for convenience
///   PING_MESSAGE      (optional, default: "hello reactive")
///
/// Usage:
///   forge script script/playground/PingEmitter.s.sol \
///     --rpc-url $UNICHAIN_SEPOLIA_RPC \
///     --private-key $DEPLOYER_PRIVATE_KEY \
///     --broadcast
contract PingEmitter is Script {
    function run() external {
        address emitterAddr = vm.envAddress("HELLO_EMITTER");
        string memory message = _envOrDefaultString("PING_MESSAGE", "hello reactive");

        HelloWorldEmitter helloEmitter = HelloWorldEmitter(emitterAddr);

        uint256 nonceBefore = helloEmitter.nonce();

        vm.startBroadcast();
        helloEmitter.ping(message);
        vm.stopBroadcast();

        console2.log("--- Ping fired ---");
        console2.log("Emitter:     ", emitterAddr);
        console2.log("Nonce before:", nonceBefore);
        console2.log("Nonce after: ", helloEmitter.nonce());
        console2.log("Message:     ", message);
        console2.log("");
        console2.log("Now watch Reactscan for the Callback emission on Lasna,");
        console2.log("then Uniscan for HelloWorldReceiver.Incremented on Unichain Sepolia.");

        try vm.envAddress("HELLO_RECEIVER") returns (address receiverAddr) {
            HelloWorldReceiver receiver = HelloWorldReceiver(payable(receiverAddr));
            console2.log("Receiver count (pre-callback):", receiver.count());
        } catch {}
    }

    function _envOrDefaultString(string memory key, string memory fallbackVal) internal view returns (string memory) {
        try vm.envString(key) returns (string memory v) {
            return v;
        } catch {
            return fallbackVal;
        }
    }
}
