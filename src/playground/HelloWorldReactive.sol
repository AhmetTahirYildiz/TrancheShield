// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AbstractReactive} from "@reactive-lib/abstract-base/AbstractReactive.sol";
import {IReactive} from "@reactive-lib/interfaces/IReactive.sol";

/// @title HelloWorldReactive
/// @notice Reactive Smart Contract deployed to Lasna. Subscribes to the
///         HelloWorldEmitter on Unichain Sepolia and forwards each Ping as a
///         callback to HelloWorldReceiver on Unichain Sepolia.
/// @dev    Deployed twice by the Reactive Network: once on the top-level RNK
///         (constructor sets up subscriptions) and once inside the RVM
///         (where react() actually fires). The `vm` flag distinguishes them.
contract HelloWorldReactive is AbstractReactive {
    /// @dev keccak256("Ping(address,uint256,string)").
    uint256 private constant PING_TOPIC_0 =
        0x70b9fa9db7248779b82f3212f84983f03b8f0b0df01c3e83a8c642df6897002a;

    /// @dev Reactive Network gas budget for the destination callback. The
    ///      protocol enforces an upper bound; using 700k leaves headroom.
    uint64 private constant CALLBACK_GAS_LIMIT = 700_000;

    uint256 public immutable originChainId;
    address public immutable emitter;
    uint256 public immutable destinationChainId;
    address public immutable receiver;

    uint256 public callbackCount;

    event Subscribed(uint256 indexed chainId, address indexed emitter, uint256 topic0);
    event Reacted(uint256 indexed srcNonce, address indexed origSender);

    constructor(
        uint256 _originChainId,
        address _emitter,
        uint256 _destinationChainId,
        address _receiver
    ) payable {
        originChainId = _originChainId;
        emitter = _emitter;
        destinationChainId = _destinationChainId;
        receiver = _receiver;

        // Only subscribe from the RNK side; RVM instance has no service contract.
        if (!vm) {
            service.subscribe(
                _originChainId,
                _emitter,
                PING_TOPIC_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
            emit Subscribed(_originChainId, _emitter, PING_TOPIC_0);
        }
    }

    /// @notice Hook invoked by the Reactive VM whenever a matching log is observed.
    /// @dev    Indexed args arrive in topic_1/2/3; non-indexed args (the
    ///         message string) come via `data` ABI-encoded. Matches the
    ///         canonical Reactive demo pattern: only `vmOnly` is applied here.
    function react(LogRecord calldata log) external vmOnly {
        // Ping(address indexed sender, uint256 indexed nonce, string message)
        address origSender = address(uint160(log.topic_1));
        uint256 srcNonce = log.topic_2;
        string memory message = abi.decode(log.data, (string));

        bytes memory payload = abi.encodeWithSignature(
            "increment(address,address,uint256,string)",
            address(0), // placeholder for RVM ID injection
            origSender,
            srcNonce,
            message
        );

        unchecked {
            ++callbackCount;
        }
        emit Reacted(srcNonce, origSender);

        emit Callback(destinationChainId, receiver, CALLBACK_GAS_LIMIT, payload);
    }
}
