# TrancheShield — Deployment Registry

Live testnet addresses. Updated after each deploy.

## Phase 4 — Full system (Hook + Reserve + Reactive controller)

**Status:** ✅ Cross-chain roundtrip verified live 2026-05-29. A volatility spike on
Unichain Sepolia drove the Lasna RSC to flip the hook into CRISIS via bounded callbacks.

### Unichain Sepolia (chain 1301)

| Contract | Address | Notes |
|---|---|---|
| ProtectionReserve | [`0x3de4acc32c8cf9228c63d673b7cda01f2d17ae6d`](https://sepolia.uniscan.xyz/address/0x3de4acc32c8cf9228c63d673b7cda01f2d17ae6d) | per-pool reserve + liability/collateral bookkeeping |
| TrancheShieldHook | [`0x696d7e04c2637630fec303628bf774ae57c48fc0`](https://sepolia.uniscan.xyz/address/0x696d7e04c2637630fec303628bf774ae57c48fc0) | mined (low 14 bits `0xfc0` = 6 perms); admin-updatable callbackReceiver |
| CallbackReceiver | [`0xdd3da7354ce7807dbe8ae50eae83cd9c7c7ff9cd`](https://sepolia.uniscan.xyz/address/0xdd3da7354ce7807dbe8ae50eae83cd9c7c7ff9cd) | `rvmIdOnly` only; funded 0.2 ETH |
| V4Quoter (official lens) | [`0x82e1dd8da6b484c7a5d52fd661023f10f780ced3`](https://sepolia.uniscan.xyz/address/0x82e1dd8da6b484c7a5d52fd661023f10f780ced3) | proves routability — `quoteExactInputSingle` on the demo pool returns 1.0 token0 → **1.0247 token1** (gas est. 79614). `script/QuoteCheck.s.sol` |

### Lasna (chain 5318007)

| Contract | Address | Status | Notes |
|---|---|---|---|
| ReactiveRiskController | [`0xC2D2eDA8677c93172A0acE228Eb8CB58621705dC`](https://lasna.reactscan.net/address/0xC2D2eDA8677c93172A0acE228Eb8CB58621705dC) | ✅ active | `CALLBACK_GAS_LIMIT = 900_000`, value-change callback gating, cron disabled (topic 0) |

Earlier RSC deploys are dead (wrong sim addresses / OOG callback gas): `0x26dE…b8Cb`,
`0x998E…f853`, `0x4e7B…89E2`, `0x73D7…86E0`. Each holds ~5 lREACT (sunk).

### Demo pool (Unichain Sepolia)

- poolId: `0x3296bf4dcea4911b02a1df529a67457118779175048a0689f5e2bb38259da195`
- token0 `0x9903fa2e3c3291cffbde6958676adc92737a82a0`, token1 `0xb9cc9045d84485e5864b5ef2ecc77931824b89e2`
- dynamic-fee pool (`DYNAMIC_FEE_FLAG`), tickSpacing 60, deep Junior liquidity + one Senior position

### Verified roundtrip

- Source: alternating swaps via `script/TriggerSwaps.s.sol` emit `SwapRiskObserved` /
  `ReserveRatioUpdated` on Unichain Sepolia.
- RSC reacts on Lasna, emits `setRiskMode` / `updateCoverageRatio` / `setSeniorDepositStatus`.
- Destination effect on the hook (`getPoolRiskState`): **mode → CRISIS (3)**, **coverageRatioBps → 1000**,
  **seniorDepositsEnabled → false**. Three `RiskParameterUpdated` events on the receiver
  (blocks 53493662-64), e.g. tx `0xbc65b41b8e86269012f47dc1ca01f7a1671e7f22588c7ca0f677bbba5bd6e682`.

### Real comparison scenario (on-chain IL-protection proof)

`script/RealComparison.s.sol` runs a genuine end-to-end IL-protection scenario on a
fresh pool of the live hook, so the frontend can show real `PositionClosed` data
instead of a model. Broadcast 2026-06-08.

- poolId: `0x0fe678433179b93a0b6f4ced6c23ad08413ccc7b657e292e3dc925518af6cbb9`
- owner: `0xafE8CB084EFfbDe745baAaaB73c80a97Ab3582a4`
- token0 `0x668320E26186136AE2392eaF7A63a611d09e174D`, token1 `0xA788D2f392d56F80f6c79B6a33620E910aa5bF4F`
- Flow: Junior deep liquidity (first-loss buffer) + Senior position → 7 one-directional
  swaps push the tick 0 → −14475 (~−76%) → Senior withdraws.
- **Real result** (PositionClosed, block 54019021, tx
  [`0x41f83c69…cdff59ed`](https://sepolia.uniscan.xyz/tx/0x41f83c694e25cf8459e470dde3b519cfa8b419f9e1daeb14cc3ff383cdff59ed)):
  ilShortfall **3.174 token1**, compensation **1.587 token1**, recovery **5000 bps (50%)**.
- Reserve left empty by design → compensation drawn from the Junior tranche (Tier 2):
  `juniorCollateral` decremented on-chain. Tier-2 token settlement is bookkeeping in the
  MVP; the Tier-1 reserve path transfers tokens directly.

### Lessons learned (Phase 4 debugging — cost ~hours)

1. **`CALLBACK_GAS_LIMIT` must cover the nested call.** 250k OOGs the
   proxy→receiver→hook chain (`ReentrancySentryOOG`); the proxy logs `CallbackFailure`.
   Use 900k. `cast call --trace` / `cast estimate` hide this (eth_call ignores the gas
   limit) — use **`cast run <txhash>`** on a recent block to see the real revert.
2. **Receiver setters: `rvmIdOnly` only.** Adding `authorizedSenderOnly` rejects every live
   callback (the real callback sender ≠ the registered proxy on this testnet).
3. **A failed (OOG) callback charges the receiver → transient "in debt" → blocks the next
   callback.** Fixing the gas removes both; `coverDebt()` clears stuck debt manually.
4. **Capture deployed addresses from the broadcast artifact**, never from a second
   no-broadcast script run (nonce drift prints undeployed sim addresses).
5. RSC callback gating must be **value-change based**, not block-rate-limited — the RVM
   batches events into adjacent blocks, so a block-number rate limit suppresses everything
   after the first callback.

---

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
