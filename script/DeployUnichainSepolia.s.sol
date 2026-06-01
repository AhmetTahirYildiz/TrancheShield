// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/utils/HookMiner.sol";

import {TrancheShieldHook} from "../src/hooks/TrancheShieldHook.sol";
import {ProtectionReserve} from "../src/reserve/ProtectionReserve.sol";
import {CallbackReceiver} from "../src/reactive/CallbackReceiver.sol";
import {IProtectionReserve} from "../src/interfaces/IProtectionReserve.sol";

/// @notice Deploys the Unichain Sepolia (chain 1301) side of TrancheShield:
///         ProtectionReserve, the mined TrancheShieldHook, and the CallbackReceiver.
///
/// Deploy order matters — the hook constructor consumes the reserve address (so the
/// reserve is deployed first), and the CallbackReceiver consumes the hook address (so it
/// is deployed last). Back-references are then closed via setHook / setCallbackReceiver.
///
/// Usage:
///   forge script script/DeployUnichainSepolia.s.sol \
///     --rpc-url $UNICHAIN_SEPOLIA_RPC \
///     --private-key $DEPLOYER_PRIVATE_KEY \
///     --broadcast
contract DeployUnichainSepolia is Script {
    /// @dev Uniswap v4 PoolManager on Unichain Sepolia (PROJECT-v2.md §22.1).
    address constant DEFAULT_POOL_MANAGER = 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
    /// @dev Reactive Callback Proxy on Unichain Sepolia (PROJECT-v2.md §22.1).
    address constant DEFAULT_CALLBACK_PROXY = 0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4;
    /// @dev Canonical CREATE2 deployer proxy used by `forge script` for salted creations.
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @dev Prefund the CallbackReceiver so it can settle the Callback Proxy's debt.
    uint256 constant RECEIVER_PREFUND = 0.05 ether;

    function run() external {
        address poolManager = _envOrDefault("POOL_MANAGER", DEFAULT_POOL_MANAGER);
        address callbackProxy = _envOrDefault("CALLBACK_PROXY", DEFAULT_CALLBACK_PROXY);

        // The six hook permission bits TrancheShieldHook declares.
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
                | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
        );

        // The deploying EOA becomes the hook admin (CREATE2 means the hook's constructor
        // msg.sender is the factory, so admin must be passed explicitly).
        address admin = msg.sender;

        vm.startBroadcast();

        // 1. Reserve (plain CREATE).
        ProtectionReserve reserve = new ProtectionReserve();

        // 2. Mine a salt so the hook address encodes the permission bits in its low 14 bits.
        bytes memory constructorArgs =
            abi.encode(IPoolManager(poolManager), IProtectionReserve(address(reserve)), admin);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(TrancheShieldHook).creationCode, constructorArgs);

        // 3. Deploy the hook via CREATE2 (forge routes salted creations through CREATE2_DEPLOYER).
        TrancheShieldHook hook =
            new TrancheShieldHook{salt: salt}(IPoolManager(poolManager), IProtectionReserve(address(reserve)), admin);
        require(address(hook) == hookAddress, "hook address mismatch");

        // 4. Close the reserve -> hook back-reference.
        reserve.setHook(address(hook));

        // 5. CallbackReceiver, prefunded; then close the hook -> receiver reference.
        CallbackReceiver receiver = new CallbackReceiver{value: RECEIVER_PREFUND}(callbackProxy, address(hook));
        hook.setCallbackReceiver(address(receiver));

        vm.stopBroadcast();

        console2.log("--- TrancheShield (Unichain Sepolia) ---");
        console2.log("PoolManager:     ", poolManager);
        console2.log("CallbackProxy:   ", callbackProxy);
        console2.log("ProtectionReserve:", address(reserve));
        console2.log("TrancheShieldHook:", address(hook));
        console2.log("CallbackReceiver: ", address(receiver));
        console2.log("Receiver balance: ", address(receiver).balance);
        console2.log("");
        console2.log("Set these in your .env for the Lasna deploy:");
        console2.log("  HOOK_ADDRESS=", address(hook));
        console2.log("  RESERVE_ADDRESS=", address(reserve));
        console2.log("  CALLBACK_RECEIVER=", address(receiver));
    }

    function _envOrDefault(string memory key, address fallbackAddr) internal view returns (address) {
        try vm.envAddress(key) returns (address v) {
            return v;
        } catch {
            return fallbackAddr;
        }
    }
}
