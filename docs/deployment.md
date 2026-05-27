# TrancheShield — Deployment Registry

Live testnet addresses. Updated after each deploy.

## Phase 1 — Hello World RSC (de-risker)

**Status:** ✅ Roundtrip verified 2026-05-27. Definition of done met.

### Unichain Sepolia (chain 1301)

| Contract | Address | Notes |
|---|---|---|
| HelloWorldEmitter | [`0x8024Fe4c35276A0fDFB64D14C33C2e2f7E7977E9`](https://sepolia.uniscan.xyz/address/0x8024Fe4c35276A0fDFB64D14C33C2e2f7E7977E9) | `Ping(address,uint256,string)` source |
| HelloWorldReceiver | [`0x19fC3cB0De4d631342209B956346cC6803Fd42b5`](https://sepolia.uniscan.xyz/address/0x19fC3cB0De4d631342209B956346cC6803Fd42b5) | Pre-funded 0.05 ETH for callback gas |

### Lasna (chain 5318007)

| Contract | Address | Status | Notes |
|---|---|---|---|
| HelloWorldReactive (v1) | `0x8024Fe4c35276A0fDFB64D14C33C2e2f7E7977E9` | ❌ broken | First deploy; `react()` had `authorizedSenderOnly` blocking RVM caller. Subscription is live but no callbacks fire. ~5 lREACT locked. |
| HelloWorldReactive (v2) | [`0x19fC3cB0De4d631342209B956346cC6803Fd42b5`](https://lasna.reactscan.net/address/0x19fC3cB0De4d631342209B956346cC6803Fd42b5) | ✅ active | `react()` gated with `vmOnly` only. Subscribed to Ping events from emitter; emits Callback to destination receiver. |

### Verified roundtrip

- Source ping tx (Unichain Sepolia): `0x7ac7e6940c39264881ba508061f41b1c115b85a8c8a0a79aa0c34d7b9ab36e7d`
- Destination callback effect: `HelloWorldReceiver.count == 1`, `lastNonce == 3`, `lastMessage == "after redeploy"`
- Latency from ping confirmation → destination callback: under 12 seconds

### Deploy commands used (for repro)

```powershell
# 1. lREACT faucet (Sepolia → Lasna credit)
cast send 0x9b9BB25f1A81078C544C829c5EB7822d747Cf434 `
  --rpc-url $env:SEPOLIA_RPC `
  --private-key $env:DEPLOYER_PRIVATE_KEY `
  --value 0.5ether `
  "request(address)" $env:DEPLOYER_ADDRESS

# 2. Emitter + Receiver on Unichain Sepolia
forge script script/playground/DeployHello.s.sol:DeployHello `
  --rpc-url $env:UNICHAIN_SEPOLIA_RPC `
  --private-key $env:DEPLOYER_PRIVATE_KEY `
  --broadcast

# 3. Reactive on Lasna — MUST use forge create, not forge script
#    (forge script's local simulation has no precompile at 0x64)
forge create src/playground/HelloWorldReactive.sol:HelloWorldReactive `
  --rpc-url $env:LASNA_RPC `
  --private-key $env:DEPLOYER_PRIVATE_KEY `
  --broadcast --value 5ether --legacy `
  --constructor-args 1301 0x8024Fe4c35276A0fDFB64D14C33C2e2f7E7977E9 1301 0x19fC3cB0De4d631342209B956346cC6803Fd42b5

# 4. Trigger ping
forge script script/playground/PingEmitter.s.sol:PingEmitter `
  --rpc-url $env:UNICHAIN_SEPOLIA_RPC `
  --private-key $env:DEPLOYER_PRIVATE_KEY `
  --broadcast
```

### Lessons learned (carried forward to Phase 4)

1. `react()` must be gated with `vmOnly` **only**. Adding `authorizedSenderOnly` silently breaks the roundtrip because the RVM caller is not in the senders ACL.
2. RSC-side state mutated in `react()` (e.g. `callbackCount`) lives on the RVM, not on the RNK-visible address. Lasna RPC reads of that state will show the unchanged RNK-side value. To verify a callback fired, check destination state.
3. Use `forge create`, not `forge script`, for any contract whose constructor calls `service.subscribe()`. Local simulation lacks the `0x64` precompile and the constructor reverts with "Failure".
4. Allow ~60-90s for subscription propagation after RSC deployment before emitting source events. Events emitted before propagation are silently dropped.
