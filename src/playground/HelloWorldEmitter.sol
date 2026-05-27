// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title HelloWorldEmitter
/// @notice Minimal Unichain Sepolia event source used to de-risk the Reactive
///         Network roundtrip (origin → Lasna RSC → destination callback).
contract HelloWorldEmitter {
    event Ping(address indexed sender, uint256 indexed nonce, string message);

    uint256 public nonce;

    function ping(string calldata message) external {
        unchecked {
            ++nonce;
        }
        emit Ping(msg.sender, nonce, message);
    }
}
