// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AbstractCallback} from "@reactive-lib/abstract-base/AbstractCallback.sol";

/// @title HelloWorldReceiver
/// @notice Destination contract on Unichain Sepolia. Receives callbacks fired by
///         HelloWorldReactive on Lasna via the Callback Proxy.
/// @dev    The first parameter of every callback is reserved for the RVM ID
///         injected by the Reactive Network; downstream params follow.
contract HelloWorldReceiver is AbstractCallback {
    event Incremented(address indexed rvmId, address indexed origSender, uint256 newCount, string message);

    uint256 public count;
    uint256 public lastNonce;
    string public lastMessage;

    constructor(address _callbackSender) AbstractCallback(_callbackSender) payable {}

    /// @notice Callback invoked by the Reactive Network's Callback Proxy on this chain.
    /// @param rvmId        RVM identifier injected by the proxy (first param contract).
    /// @param origSender   The EOA / contract that triggered the original Ping on the source chain.
    /// @param srcNonce     Nonce from the source Ping event (for ordering / debugging).
    /// @param message      Free-form message from the source Ping event.
    function increment(
        address rvmId,
        address origSender,
        uint256 srcNonce,
        string calldata message
    ) external authorizedSenderOnly rvmIdOnly(rvmId) {
        unchecked {
            ++count;
        }
        lastNonce = srcNonce;
        lastMessage = message;
        emit Incremented(rvmId, origSender, count, message);
    }
}
