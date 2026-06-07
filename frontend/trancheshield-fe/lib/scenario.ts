/**
 * Illustrative economic model for the comparison view. These are NOT live
 * numbers — they are deterministic scenarios computed from the protocol's own
 * mechanics so judges can see the value proposition at a glance:
 *
 *   - Full-range (v2-style) impermanent loss:  IL = entry1 * (sqrt(r) - 1)^2
 *     (mirrors src/libraries/ILMath.sol's HODL-vs-LP shortfall).
 *   - Dynamic-fee premium routing: a slice of swap yield is diverted from the
 *     Senior tranche to the reserve as an insurance premium; the Junior tranche
 *     earns that premium in exchange for taking first-loss.
 *   - Coverage + per-position cap: Senior IL is compensated at coverageBps,
 *     capped at perPositionCapBps of entry value (20% in the hook).
 *   - Loss waterfall: compensation is paid from the reserve first; any shortfall
 *     is absorbed by Junior collateral (Tier 2).
 *
 * All amounts are denominated in token1 (think USDC) for a balanced deposit
 * where amount0 * p0 == amount1, so the initial position value V0 = 2 * entry1.
 */

export type Regime = 0 | 1 | 2 | 3;

export interface ScenarioInput {
  key: string;
  label: string;
  tagline: string;
  regime: Regime;
  /** token1 side of a balanced deposit; position value V0 = 2 * entry1. */
  entry1: number;
  p0: number;
  p1: number;
  /** Gross swap fees earned over the period, in bps of V0. */
  grossFeeBps: number;
  /** Insurance premium, in bps of V0 — Senior pays it, Junior earns it. */
  premiumBps: number;
  /** IL coverage ratio applied to the Senior position. */
  coverageBps: number;
  /** Per-position coverage cap, in bps of entry1 (2000 = 20%). */
  perPositionCapBps: number;
  /** Share of the desired compensation the reserve can fund; the rest is
   *  absorbed by Junior collateral. 10000 = fully reserve-funded. */
  reserveFundedBps: number;
}

export interface PositionResult {
  hodl: number;
  lpValue: number;
  il: number;
  fees: number;
  /** +earned (Junior) / -paid (Senior) / 0 (unprotected). */
  premium: number;
  compensation: number;
  /** First-loss absorbed by Junior collateral (negative effect). */
  juniorAbsorbed: number;
  /** Net P&L vs simply holding the two tokens (HODL). */
  netVsHodl: number;
  finalValue: number;
}

export interface ScenarioResult {
  input: ScenarioInput;
  v0: number;
  priceMovePct: number;
  ilPct: number;
  il: number;
  plain: PositionResult;
  senior: PositionResult;
  junior: PositionResult;
  /** How much less the Senior LP lost vs the unprotected LP (token1). */
  seniorSavingAbs: number;
  /** Same, as a % reduction of the unprotected LP's loss. */
  seniorSavingPct: number;
}

export function computeScenario(input: ScenarioInput): ScenarioResult {
  const { entry1, p0, p1 } = input;
  const v0 = 2 * entry1;
  const r = p1 / p0;
  const sqrtR = Math.sqrt(r);

  const hodl = entry1 * (r + 1);
  const lpValue = 2 * entry1 * sqrtR;
  const il = Math.max(0, hodl - lpValue); // = entry1 * (sqrtR - 1)^2

  const grossFees = (v0 * input.grossFeeBps) / 10_000;
  const premium = (v0 * input.premiumBps) / 10_000;
  const cap = (entry1 * input.perPositionCapBps) / 10_000;

  const desiredComp = (il * input.coverageBps) / 10_000;
  const compensation = Math.min(desiredComp, cap);
  const reservePortion = (compensation * input.reserveFundedBps) / 10_000;
  const juniorAbsorbed = compensation - reservePortion;

  const plain: PositionResult = {
    hodl,
    lpValue,
    il,
    fees: grossFees,
    premium: 0,
    compensation: 0,
    juniorAbsorbed: 0,
    netVsHodl: -il + grossFees,
    finalValue: lpValue + grossFees,
  };

  const senior: PositionResult = {
    hodl,
    lpValue,
    il,
    fees: grossFees,
    premium: -premium,
    compensation,
    juniorAbsorbed: 0,
    netVsHodl: -il + grossFees - premium + compensation,
    finalValue: lpValue + grossFees - premium + compensation,
  };

  const junior: PositionResult = {
    hodl,
    lpValue,
    il,
    fees: grossFees,
    premium,
    compensation: 0,
    juniorAbsorbed,
    netVsHodl: -il + grossFees + premium - juniorAbsorbed,
    finalValue: lpValue + grossFees + premium - juniorAbsorbed,
  };

  const seniorSavingAbs = senior.netVsHodl - plain.netVsHodl;
  const seniorSavingPct =
    plain.netVsHodl < 0 ? (seniorSavingAbs / -plain.netVsHodl) * 100 : 0;

  return {
    input,
    v0,
    priceMovePct: (r - 1) * 100,
    ilPct: (il / hodl) * 100,
    il,
    plain,
    senior,
    junior,
    seniorSavingAbs,
    seniorSavingPct,
  };
}

export const SCENARIOS: ScenarioInput[] = [
  {
    key: "moderate",
    label: "Moderate volatility",
    tagline: "+70% drift · MEDIUM regime · reserve healthy",
    regime: 1,
    entry1: 5_000,
    p0: 2_000,
    p1: 3_400,
    grossFeeBps: 150,
    premiumBps: 60,
    coverageBps: 5_000,
    perPositionCapBps: 2_000,
    reserveFundedBps: 10_000,
  },
  {
    key: "rally",
    label: "Strong rally",
    tagline: "+150% move · HIGH regime · large IL",
    regime: 2,
    entry1: 5_000,
    p0: 2_000,
    p1: 5_000,
    grossFeeBps: 180,
    premiumBps: 70,
    coverageBps: 3_500,
    perPositionCapBps: 2_000,
    reserveFundedBps: 10_000,
  },
  {
    key: "crisis",
    label: "Crisis crash",
    tagline: "-65% crash · CRISIS · coverage floored, Junior absorbs",
    regime: 3,
    entry1: 5_000,
    p0: 2_000,
    p1: 700,
    grossFeeBps: 200,
    premiumBps: 80,
    coverageBps: 1_500,
    perPositionCapBps: 2_000,
    reserveFundedBps: 4_000,
  },
];
