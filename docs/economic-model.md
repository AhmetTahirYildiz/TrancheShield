# TrancheShield — Economic Model

> How TrancheShield turns impermanent loss from an unpriced, unhedged tax into a
> two-sided market that lives **inside a single Uniswap v4 pool**. This document
> derives every number from the contracts in [`src/`](../src); the constants cited
> here are the literal constants in the code, not illustrative figures.

---

## 1. The problem: impermanent loss is an unpriced tax

A passive Uniswap LP is short volatility. When the price of the pair moves, the
constant-product curve rebalances the LP *into* the depreciating asset, and the
position ends up worth less than simply holding the entry basket. That gap —
**impermanent loss (IL)** — is real, recurring, and silent: it never appears as a
line item, it is netted against fee income, and most LPs only discover it when
they withdraw.

Existing mitigations sit *outside* the pool:

| Approach | Where the capital lives | Problem |
| --- | --- | --- |
| Buy options / variance swaps | External venue | Illiquid for long-tail pairs; basis risk; manual roll |
| LP into "IL-protected" vaults | Separate protocol | Protection funded by token emissions → mercenary, inflationary |
| Just accept it | — | LPs quietly subsidize swappers |

TrancheShield's thesis: **IL is insurable, and the premium can be priced and
collected from the same swap flow that causes it.** No external venue, no emissions
— the protection is a structural property of the pool.

---

## 2. Design: a two-sided risk market on one pool

Every LP who enters the pool picks a **tranche** (encoded in `hookData` as
`abi.encode(Tranche, owner)`; `Senior = 0`, `Junior = 1`):

- **Senior LPs — protection buyers.** They keep most of the swap-fee yield but
  give up a slice of it as a *premium*, and in exchange a portion of their IL is
  reimbursed at exit from the reserve. They are the risk-averse capital.
- **Junior LPs — protection sellers / underwriters.** They post their full
  deposit as **collateral** that backstops Senior IL, and in exchange they earn an
  extra premium share on top of base fees. They are the risk-seeking capital that
  is long the pool and long the premium stream.

This is the classic securitization split (senior/junior tranches of a structured
product), applied to an AMM position. The novelty is that the **waterfall, the
premium, and the risk pricing all execute on-chain inside the hook** — there is no
off-chain underwriter.

```
            premium (swap-fee slice)
  swappers ───────────────────────────►  Protection Reserve
                                             │  (Tier 1 backstop)
  Senior LP  ── deposit ──►  pool           │
     ▲           protected                   │ pays IL compensation at exit
     └──────────── IL compensation ──────────┘
                                             ▲
  Junior LP  ── deposit ──►  pool           │ (Tier 2 backstop, capped)
                collateral ─────────────────┘  earns the premium for the risk
```

---

## 3. Capital stack & the loss waterfall

When a **Senior** position closes ([`TrancheShieldHook._settleSenior`](../src/hooks/TrancheShieldHook.sol)),
the hook computes the IL shortfall and pays compensation through a strict
waterfall. Two hard caps and a health-scaled coverage ratio sit between "IL
happened" and "reserve pays":

1. **Coverage ratio** (`coverageRatioBps`, default `5_000` = 50%): the protocol
   only ever targets a *fraction* of IL, never 100%. This is the headline
   risk-share between protocol and LP.
2. **Per-position cap** (`PER_POSITION_COVERAGE_CAP_BPS = 2_000` = 20% of the
   position's entry value): no single Senior position can claim more than 20% of
   what it deposited, regardless of how violent the move was.
3. **Waterfall source order:**
   - **Tier 1 — Protection Reserve** (`reserve.payCompensation`, a *real* token
     transfer). Funded by premiums (§5).
   - **Tier 2 — Junior collateral** (`juniorCollateral`), only for the remainder
     the reserve couldn't cover, and itself capped per event at
     `JUNIOR_PER_EVENT_CAP_BPS = 2_000` = 20% of the pool's Junior collateral so a
     single exit can't wipe the underwriters.

```
  desired = min( IL × coverageRatioBps , perPositionCap )

  fromReserve = min(desired, reserveBalance)            ← Tier 1 (real transfer)
  remaining   = desired − fromReserve
  fromJunior  = min(remaining, 20% of juniorCollateral) ← Tier 2 (collateral draw)

  compensation = fromReserve + fromJunior
```

Because each layer is independently capped, the system **degrades gracefully**
instead of going bankrupt: if the reserve is thin and Junior is small, Senior
simply receives less — it never reverts, never goes negative, and never lets one
position socialize an unbounded loss onto the others.

---

## 4. Pricing IL: the on-chain IL formula

IL is measured in **token1 terms** ([`ILMath`](../src/libraries/ILMath.sol)) at exit,
using the pool's own `sqrtPriceX96`:

```
HODL value     = amount0_entry · P_exit + amount1_entry
LP exit value  = amount0_exit  · P_exit + amount1_exit
IL shortfall   = max(0, HODL value − LP exit value)
```

- `P_exit = (sqrtPriceX96 / 2^96)^2`, computed in two `FullMath.mulDiv` steps to
  avoid the uint256 overflow a naïve square would cause.
- The shortfall is **floored at zero**: if the LP came out ahead of HODL (fees +
  favorable range), there is no payout. Protection covers losses, not profits.
- The entry value snapshot (`entryValueToken1`) is taken in `afterAddLiquidity`
  and is what both the per-position cap and the Senior liability are sized
  against.

This is the divergence-loss definition (LP vs. HODL), not a price-only
approximation — it nets fees earned into `LP exit value` automatically, because
those fees are part of what the LP actually withdraws.

---

## 5. Premiums: where the yield comes from

The premium is a **slice of the dynamic swap fee**, routed on every swap in
[`_afterSwap`](../src/hooks/TrancheShieldHook.sol):

```
grossFee = amountIn · feePips / 1_000_000
premium  = grossFee · reserveShareBps / 10_000   → reserve.routePremium(...)
```

The fee itself is dynamic (§6). The *split* of that fee shifts with risk mode so
the reserve fills faster precisely when IL is most likely
([`LP_SHARE_*` / `RESERVE_SHARE_*`](../src/hooks/TrancheShieldHook.sol)):

| Risk mode | Active-LP share | Reserve share | Junior share* |
| --- | --- | --- | --- |
| LOW | 80% | 10% | 10% |
| MEDIUM | 70% | 20% | 10% |
| HIGH | 60% | 25% | 15% |
| CRISIS | 50% | 35% | 15% |

<sub>\* Junior share is the residual `100% − LP − reserve`; it is the underwriters'
compensation for carrying Tier-2 risk.</sub>

**Yield sources, plainly:**
- **Senior** keeps the LP share of fees, minus the premium it pays — net, a
  slightly-reduced fee yield in exchange for downside cover.
- **Junior** earns base fees on its own liquidity **plus** the Junior premium
  share — a higher, riskier yield, paid for taking the Tier-2 backstop.
- **The reserve** is funded purely by the reserve share of real swap flow — *no
  token emissions*. The protection is self-funding from the activity that creates
  the risk.

The actuarial intuition: in calm markets premiums accrue faster than IL is
claimed, so the reserve builds a buffer; in volatile markets the fee (and the
reserve's share of it) rises, partially self-financing the higher claim rate.

---

## 6. Reactive risk pricing (the four signals)

Fees and coverage are **not static**. The [`ReactiveRiskController`](../src/reactive/ReactiveRiskController.sol)
(a Reactive Network smart contract on Lasna) subscribes to the hook's events,
maintains **per-pool** state, and pushes parameter updates back cross-chain. Four
independent signals reprice the pool:

**(a) Volatility → risk mode + fee multiplier.** A Welford rolling stdev of the
post-swap tick produces a `score`; the fee multiplier scales the 30 bps base fee:

| Score (tick stdev) | Mode | Fee multiplier | Effective fee |
| --- | --- | --- | --- |
| `< 50` | LOW | 1.00× | 30 bps |
| `≥ 50` | MEDIUM | 1.25× | 37.5 bps |
| `≥ 150` | HIGH | 1.75× | 52.5 bps |
| `≥ 300` | CRISIS | 2.50× | 75 bps |

**(b) Reserve health → coverage ratio.** As the reserve-to-liability ratio falls,
the protocol *automatically promises less* so it can keep its promises
([`_onReserveRatio`](../src/reactive/ReactiveRiskController.sol)):

| Reserve ratio | Coverage target |
| --- | --- |
| `≥ 150%` | 50% |
| `≥ 100%` | 35% |
| `≥ 70%` | 20% |
| `< 70%` (critical) | 10% **+ force CRISIS + halt new Senior deposits** |

**(c) Toxic flow → surcharge.** `TOXIC_THRESHOLD = 3` consecutive same-direction
swaps add a `+0.25×` (`2_500` bps) surcharge on top of the mode multiplier,
capped at the global `3.00×` ceiling — directional sweeping (the flow most
correlated with LP loss) pays more.

**(d) Bank run → circuit breaker.** `≥ 5` Senior withdrawals within a 3,600 s
window force CRISIS, drop coverage to 15%, and halt new Senior deposits
([`_onSeniorWithdrawal`](../src/reactive/ReactiveRiskController.sol)) — preventing
a run from draining the reserve faster than it can be defended.

Crucially, all four are **keyed per pool**: a spike on one pool can neither
trigger nor suppress a mode change on another, and a fresh pool always starts in
LOW regardless of network history.

---

## 7. Solvency: why the reserve cannot be drained to insolvency

The model is designed so that no sequence of exits can produce a negative balance
or an unbounded claim. The guarantees compose:

1. **Coverage < 100%** — the protocol never targets full IL; LPs always retain
   first-loss skin.
2. **Per-position cap = 20% of entry value** — bounds any single claim.
3. **Coverage auto-deleverages with reserve health** — at `< 70%` reserve ratio,
   coverage collapses to 10% and the pool enters CRISIS, throttling new liability.
4. **Tier-2 Junior draw capped at 20% per event** — underwriters can't be wiped by
   one exit.
5. **CRISIS halts new Senior deposits** — liability stops growing exactly when the
   reserve is weakest (enforced redundantly: the hook flips
   `seniorDepositsEnabled = false` itself whenever mode is set to CRISIS, so the
   invariant holds regardless of callback ordering).
6. **`payCompensation` reverts on `InsufficientReserve`** and only ever transfers
   what the per-(pool,currency) ledger holds — accounting can't outrun custody.

Net effect: the worst case for a Senior LP is *reduced* compensation, never a
revert that traps the withdrawal; the worst case for the system is a temporarily
under-funded reserve that the dynamic premium is actively refilling.

---

## 8. Worked example (matches the on-chain proof)

This is the scenario captured live on Unichain Sepolia and surfaced in the
frontend's **IL Protection** tab (a real `PositionClosed` event — see
[`script/RealComparison.s.sol`](../script/RealComparison.s.sol) and
[`docs/deployment.md`](./deployment.md)):

```
Senior position, coverage = 50% (LOW mode default)

  7 one-directional swaps push the tick down ~76%; Senior withdraws.
  HODL value − LP exit value  ............  IL shortfall = 3.174 token1

  desired      = IL × 50%                 = 1.587 token1
  per-pos cap  = 20% × entry value         → not binding here
  waterfall    : reserve left EMPTY by design (to exercise Tier 2)
                 fromReserve = 0
                 fromJunior  = min(1.587, 20% of juniorCollateral) = 1.587

  Compensation paid ......................  1.587 token1   (≈50% IL recovery)
  Net LP loss after protection ...........  3.174 − 1.587 = 1.587 token1
```

Without TrancheShield the LP eats the full **3.174**; with it, the on-chain
`PositionClosed(... ilShortfall = 3.174, compensationPaid = 1.587)` event shows
the loss **halved**. This recorded scenario deliberately ran with an *empty*
reserve so the payout falls through to **Tier 2** — the Junior tranche's
collateral absorbing the Senior's IL is exactly the underwriting relationship the
model is built on. With a premium-funded reserve, the same 1.587 would be paid
from Tier 1 first; the LP outcome is identical either way.

> The companion **Junior** close emits `PositionClosed(... 0, 0)`: Junior carries
> the risk and the premium, not an IL claim of its own — its Tier-2 collateral is
> released by bookkeeping at exit.

---

## 9. Parameter reference

All values are the literal constants in the contracts (source of truth wins over
this table if they ever diverge):

| Parameter | Value | Where |
| --- | --- | --- |
| Base fee | 30 bps (`3_000` pips) | `TrancheShieldHook.BASE_FEE_PIPS` |
| Default coverage ratio | 50% (`5_000` bps) | `DEFAULT_COVERAGE_RATIO_BPS` |
| Per-position coverage cap | 20% of entry (`2_000` bps) | `PER_POSITION_COVERAGE_CAP_BPS` |
| Junior per-event cap | 20% of collateral (`2_000` bps) | `JUNIOR_PER_EVENT_CAP_BPS` |
| Fee multipliers | 1.00× / 1.25× / 1.75× / 2.50× | `FEE_MULT_LOW…CRISIS` |
| Toxic-flow surcharge | +0.25× after 3 same-dir swaps | `TOXIC_SURCHARGE_BPS`, `TOXIC_THRESHOLD` |
| Fee multiplier ceiling | 3.00× (`30_000` bps) | `FeeMath.MAX_FEE_MULTIPLIER_BPS` |
| Volatility thresholds | 50 / 150 / 300 | `volMedium/High/CrisisThreshold` |
| Reserve-health thresholds | 70% / 100% / 150% | `reserveCritical/Weak/ModerateThreshold` |
| Bank-run trigger | 5 withdrawals / 3,600 s | `bankRunThreshold`, `bankRunWindowSeconds` |

---

## 10. Implementation status (MVP boundary)

The economic *design* above is complete and the **risk-pricing loop is live
end-to-end** (events → Reactive RSC → cross-chain callback → hook re-parameterize),
as is the **IL waterfall and reserve payout** (proven by the real on-chain
`PositionClosed` compensation). Two pieces are deliberately scoped as bookkeeping
in the MVP and flagged as such in the code:

- **Premium skim** routes through `reserve.routePremium` with the correct
  split math, but the actual token *delta* skim via v4 hook-deltas is marked as
  Phase 4 work (`_afterSwap` comments). The reserve is pre-funded for the demo so
  the payout path is exercised with real transfers.
- **Tier-2 Junior draw** decrements aggregate `juniorCollateral` (the solvency
  accounting) without a per-owner token debit, since the MVP has no single Junior
  to charge; per-owner Junior settlement is the natural next step.

**Future work:** concentrated-liquidity IL (current math is full-range), per-owner
Junior accounting and a Junior yield-claim path, a token1-denominated reserve
ratio (the `ReserveRatioUpdated` ratio is currently liability-only), and
governance over the threshold table (already `rnOnly`-admin-tunable on the RSC).

---

*Cross-references:* contract addresses and the live demo scenario in
[`docs/deployment.md`](./deployment.md); risk-controller operational notes in the
same file; IL/fee math in [`src/libraries/`](../src/libraries).
