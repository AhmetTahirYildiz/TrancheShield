# TrancheShield 🛡️

**Risk-tranched, self-insuring liquidity for Uniswap v4 — with a cross-chain risk
brain that reprices the pool in real time.**

TrancheShield is a Uniswap v4 hook that turns **impermanent loss (IL)** from an
unpriced, unhedged tax on LPs into a **two-sided market inside a single pool**.
LPs choose a tranche on deposit:

- **Senior** LPs pay a small premium out of their fee yield and get part of their
  IL reimbursed at exit.
- **Junior** LPs underwrite that protection with their deposit as collateral and
  earn the premium for the risk.

A **Reactive Network** smart contract watches the pool's swap, reserve, and
withdrawal events across chains, maintains a per-pool volatility model, and pushes
**dynamic fee + coverage updates back into the hook** — so the price of protection
tracks live risk instead of sitting static.

> **Theme:** Impermanent Loss & Yield Systems (UHI Hookathon).
> **Track / partner:** Reactive Network (see [Partner Integrations](#-partner-integrations)).

---

## The problem

A passive AMM LP is structurally short volatility: when the price moves, the
constant-product curve rebalances them into the depreciating asset and the
position underperforms simply holding the tokens. That gap — impermanent loss — is
real, recurring, and invisible until withdrawal. Today's mitigations live *outside*
the pool (options, variance swaps, emissions-funded "IL-protected" vaults) and
bring basis risk, illiquidity, or inflationary token subsidies.

**TrancheShield's thesis:** IL is insurable, and the premium can be priced and
collected from the very swap flow that causes it — no external venue, no emissions.
Protection becomes a structural property of the pool.

Full derivation with formulas, caps, and a worked example tied to a real on-chain
event: **[`docs/economic-model.md`](docs/economic-model.md)**.

---

## How it works

```
        Unichain Sepolia (chain 1301)                    Lasna (chain 5318007)
  ┌─────────────────────────────────────┐         ┌──────────────────────────────┐
  │  TrancheShieldHook (Uniswap v4)      │  events │  ReactiveRiskController (RSC) │
  │   • beforeSwap: apply dynamic fee    │ ───────►│   • per-pool Welford vol      │
  │   • afterSwap:  emit SwapRiskObserved│         │   • classify LOW→CRISIS       │
  │   • add/remove: tranche bookkeeping  │         │   • toxic-flow / bank-run     │
  │   • afterRemove: IL waterfall payout │         └──────────────┬───────────────┘
  │                                      │                        │ bounded callback
  │  ProtectionReserve                   │◄───────────────────────┘ (cross-chain)
  │   • premium custody + payout         │   setRiskMode / updateFeeMultiplier
  │   • Senior liability / Junior coll.  │   updateCoverageRatio / haltSeniorDeposits
  └─────────────────────────────────────┘            via CallbackReceiver
```

1. **Deposit** — LP adds liquidity with `hookData = abi.encode(Tranche, owner)`.
   Senior positions register a capped liability; Junior positions register
   collateral. ([`TrancheShieldHook._afterAddLiquidity`](src/hooks/TrancheShieldHook.sol))
2. **Swap** — `beforeSwap` overrides the LP fee with a risk-scaled dynamic fee;
   `afterSwap` routes a premium slice to the reserve and emits `SwapRiskObserved`.
   ([`_beforeSwap` / `_afterSwap`](src/hooks/TrancheShieldHook.sol))
3. **React** — the Reactive RSC consumes those events, updates a **per-pool**
   volatility estimate, and when a threshold crosses, emits a bounded cross-chain
   callback. ([`ReactiveRiskController.react`](src/reactive/ReactiveRiskController.sol))
4. **Re-price** — the `CallbackReceiver` forwards the callback to the hook's
   admin setters, changing the fee multiplier, coverage ratio, or halting Senior
   deposits. ([`CallbackReceiver`](src/reactive/CallbackReceiver.sol))
5. **Exit** — on a Senior close, the hook computes IL in token1 terms and pays
   compensation through a capped waterfall: **reserve first, then Junior
   collateral**. ([`_settleSenior`](src/hooks/TrancheShieldHook.sol),
   [`ILMath`](src/libraries/ILMath.sol))

### What makes it different

- **Self-funding insurance.** The reserve fills from a share of real swap fees,
  not token emissions; the premium split shifts toward the reserve exactly as risk
  rises.
- **Risk priced in real time, off the hot path.** The heavy, stateful risk model
  (rolling volatility, toxic-flow detection, bank-run detection) runs on Reactive
  Network — the swap path only reads a cached multiplier, so swaps stay cheap.
- **Solvency by construction.** Coverage < 100%, a 20% per-position cap, a 20%
  per-event Junior cap, coverage that auto-deleverages with reserve health, and a
  CRISIS circuit-breaker that halts new Senior deposits — the waterfall degrades
  gracefully instead of going insolvent.

---

## 🤝 Partner Integrations

### Reactive Network — **integrated** (core of the design)

The cross-chain reactive risk loop *is* the project's differentiator, not a bolt-on.

| Where | File | What it does |
| --- | --- | --- |
| Reactive Smart Contract | [`src/reactive/ReactiveRiskController.sol`](src/reactive/ReactiveRiskController.sol) | `AbstractReactive` contract on Lasna. Subscribes to the hook/reserve events on Unichain Sepolia, keeps a per-pool Welford volatility model + toxic-flow + bank-run state, emits bounded `Callback`s. |
| Destination receiver | [`src/reactive/CallbackReceiver.sol`](src/reactive/CallbackReceiver.sol) | `AbstractCallback` on Unichain Sepolia; `rvmIdOnly`-gated, forwards callbacks to the hook's risk setters. |
| Library dependency | [`lib/reactive-lib`](lib/reactive-lib) (`@reactive-lib/`) | Reactive's `AbstractReactive` / `AbstractCallback` / `ISystemContract`. |
| Deploy + ops | [`script/DeployReactiveLasna.s.sol`](script/DeployReactiveLasna.s.sol), [`docs/deployment.md`](docs/deployment.md) | `forge create` deploy to Lasna, topic-0 derivation, and a documented log of the verified live cross-chain roundtrip. |

**Deployed & verified live** on Lasna (chain 5318007) — a volatility spike on
Unichain Sepolia drove the RSC to flip the hook into CRISIS via cross-chain
callbacks. Addresses and the verified roundtrip tx are in
[`docs/deployment.md`](docs/deployment.md).

### Uniswap v4

The foundation: TrancheShield is a v4 hook using 6 permissions
(`before/afterAddLiquidity`, `before/afterRemoveLiquidity`, `before/afterSwap`),
dynamic fees (`LPFeeLibrary.OVERRIDE_FEE_FLAG`), `StateLibrary` price reads, and
the official `V4Quoter` lens to prove router quotability
([`script/QuoteCheck.s.sol`](script/QuoteCheck.s.sol)).

*No other partner integrations are claimed.*

---

## Repository layout

```
src/
  hooks/TrancheShieldHook.sol      # the v4 hook: tranches, dynamic fee, IL waterfall
  reserve/ProtectionReserve.sol    # per-pool premium custody + liability/collateral
  reactive/
    ReactiveRiskController.sol      # Reactive Network RSC (Lasna) — the risk brain
    CallbackReceiver.sol            # cross-chain callback sink (Unichain Sepolia)
  libraries/
    ILMath.sol                      # impermanent-loss math (token1-denominated)
    FeeMath.sol                     # risk-multiplier → dynamic fee (pips)
    WelfordVolatility.sol           # streaming stdev for the volatility score
  interfaces/                       # ITrancheShieldHook, IProtectionReserve
test/
  unit/                             # hook, Phase 3 flows, reactive callbacks, Welford
  invariant/                        # protocol-level invariants
script/                             # deploy + demo-seed + scenario scripts
frontend/trancheshield-fe/          # Next.js dashboard (read-only + interactive wallet)
docs/
  economic-model.md                 # the economics, derived from the contracts
  deployment.md                     # live testnet registry + ops lessons
```

---

## Build & test

Requires [Foundry](https://book.getfoundry.sh/) (Solidity 0.8.26, `via_ir`,
EVM `cancun` — v4 uses transient storage).

```bash
forge install
forge build
forge test            # 50 tests: hook flows, IL waterfall, reactive callbacks,
                      # Welford volatility, + protocol invariants & fuzzing
```

The reactive contracts compile and unit-test locally against a mocked Reactive
environment; the live cross-chain behavior is deployed on testnet (below).

---

## Live deployment

Full registry, explorer links, and the verified cross-chain roundtrip are in
**[`docs/deployment.md`](docs/deployment.md)**. Key addresses:

| Contract | Chain | Address |
| --- | --- | --- |
| TrancheShieldHook | Unichain Sepolia (1301) | `0x696d7e04c2637630fec303628bf774ae57c48fc0` |
| ProtectionReserve | Unichain Sepolia (1301) | `0x3de4acc32c8cf9228c63d673b7cda01f2d17ae6d` |
| CallbackReceiver | Unichain Sepolia (1301) | `0xdd3da7354ce7807dbe8ae50eae83cd9c7c7ff9cd` |
| ReactiveRiskController | Lasna (5318007) | see `docs/deployment.md` |

A **real on-chain IL-protection event** (`PositionClosed`: IL `3.174`, compensation
`1.587`, 50% recovery) is recorded on Unichain Sepolia and surfaced in the
frontend — see the "Real comparison scenario" section of `docs/deployment.md`.

---

## Frontend

A Next.js dashboard in [`frontend/trancheshield-fe`](frontend/trancheshield-fe)
reads live on-chain state and lets a connected wallet drive the system:

- **Live Risk** — real-time pool risk state, volatility chart, activity feed, and a
  live `V4Quoter` quote proving router quotability.
- **IL Protection** — the real on-chain `PositionClosed` proof + a
  protected-vs-unprotected comparison.
- **Interactive** — connect MetaMask, mint test tokens, open a Senior position, and
  swap to spike volatility and watch a fresh pool flip LOW → CRISIS live via the
  cross-chain loop.

```bash
cd frontend/trancheshield-fe
cp .env.example .env.local   # fill in RPC + contract addresses
npm install && npm run dev
```

---

## Demo video

📹 _Link added on submission._ <!-- replace with the YouTube link before submitting -->

---

## Documentation

- **[docs/economic-model.md](docs/economic-model.md)** — the full economic design:
  tranches, the loss waterfall, IL math, premium/yield sources, reactive risk
  pricing, and solvency guarantees.
- **[docs/deployment.md](docs/deployment.md)** — live testnet addresses, the
  verified cross-chain roundtrip, and hard-won Reactive Network ops lessons.

## License

MIT.
