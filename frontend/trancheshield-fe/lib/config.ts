import type { Address, Hex } from "viem";

/**
 * Central config. Every value is read from a NEXT_PUBLIC_ env var (inlined at
 * build time) with a fallback to the live testnet deployment, so the dashboard
 * renders correctly even before a `.env.local` exists.
 *
 * Source of truth for the fallbacks: docs/deployment.md (Phase 4, verified
 * cross-chain roundtrip on 2026-05-29).
 */

function envOr(value: string | undefined, fallback: string): string {
  return value && value.length > 0 ? value : fallback;
}

function numOr(value: string | undefined, fallback: number): number {
  const n = value ? Number(value) : NaN;
  return Number.isFinite(n) ? n : fallback;
}

export const UNICHAIN_SEPOLIA_ID = 1301;
export const LASNA_ID = 5318007;

export const RPC_URL = envOr(
  process.env.NEXT_PUBLIC_UNICHAIN_RPC,
  "https://sepolia.unichain.org",
);

export const HOOK_ADDRESS = envOr(
  process.env.NEXT_PUBLIC_HOOK_ADDRESS,
  "0x696d7e04c2637630fec303628bf774ae57c48fc0",
).toLowerCase() as Address;

export const RECEIVER_ADDRESS = envOr(
  process.env.NEXT_PUBLIC_RECEIVER_ADDRESS,
  "0xdd3da7354ce7807dbe8ae50eae83cd9c7c7ff9cd",
).toLowerCase() as Address;

export const RESERVE_ADDRESS = envOr(
  process.env.NEXT_PUBLIC_RESERVE_ADDRESS,
  "0x3de4acc32c8cf9228c63d673b7cda01f2d17ae6d",
).toLowerCase() as Address;

export const RSC_ADDRESS = envOr(
  process.env.NEXT_PUBLIC_RSC_ADDRESS,
  "0xC2D2eDA8677c93172A0acE228Eb8CB58621705dC",
).toLowerCase() as Address;

export const POOL_ID = envOr(
  process.env.NEXT_PUBLIC_POOL_ID,
  "0x3296bf4dcea4911b02a1df529a67457118779175048a0689f5e2bb38259da195",
) as Hex;

export const TOKEN0 = envOr(
  process.env.NEXT_PUBLIC_TOKEN0,
  "0x9903fa2e3c3291cffbde6958676adc92737a82a0",
).toLowerCase() as Address;

export const TOKEN1 = envOr(
  process.env.NEXT_PUBLIC_TOKEN1,
  "0xb9cc9045d84485e5864b5ef2ecc77931824b89e2",
).toLowerCase() as Address;

/** Official Uniswap v4 Quoter (lens) deployed against the live PoolManager —
 *  proves the hook'd pool is quotable/routable by standard routers. */
export const QUOTER_ADDRESS = envOr(
  process.env.NEXT_PUBLIC_QUOTER_ADDRESS,
  "0x82e1dd8da6b484c7a5d52fd661023f10f780ced3",
).toLowerCase() as Address;

/** v4 dynamic-fee sentinel (0x800000) and the demo pool's tick spacing. */
export const DYNAMIC_FEE_FLAG = 0x800000;
export const TICK_SPACING = 60;

/**
 * Event-scan window. If FROM/TO are both set we read that fixed range (good for
 * replaying the historical verified roundtrip). Otherwise we scan the most
 * recent `EVENT_LOOKBACK` blocks (good for a fresh live demo).
 */
export const EVENT_FROM_BLOCK = process.env.NEXT_PUBLIC_EVENT_FROM_BLOCK
  ? BigInt(process.env.NEXT_PUBLIC_EVENT_FROM_BLOCK)
  : null;
export const EVENT_TO_BLOCK = process.env.NEXT_PUBLIC_EVENT_TO_BLOCK
  ? BigInt(process.env.NEXT_PUBLIC_EVENT_TO_BLOCK)
  : null;
export const EVENT_LOOKBACK = BigInt(
  numOr(process.env.NEXT_PUBLIC_EVENT_LOOKBACK, 9000),
);

export const POLL_INTERVAL_MS = numOr(
  process.env.NEXT_PUBLIC_POLL_INTERVAL_MS,
  6000,
);

/**
 * Real on-chain IL-protection scenario (script/RealComparison.s.sol). The
 * OnChainProof component reads the genuine PositionClosed(ilShortfall,
 * compensation) event from this fresh pool. Fixed block window keeps the
 * eth_getLogs query cheap and stable over time.
 */
export const SCENARIO_POOL_ID = envOr(
  process.env.NEXT_PUBLIC_SCENARIO_POOL_ID,
  "0x0fe678433179b93a0b6f4ced6c23ad08413ccc7b657e292e3dc925518af6cbb9",
) as Hex;

export const SCENARIO_OWNER = envOr(
  process.env.NEXT_PUBLIC_SCENARIO_OWNER,
  "0xafE8CB084EFfbDe745baAaaB73c80a97Ab3582a4",
).toLowerCase() as Address;

export const SCENARIO_FROM_BLOCK = BigInt(
  numOr(process.env.NEXT_PUBLIC_SCENARIO_FROM_BLOCK, 54019000),
);
// A tight, already-mined window around the PositionClosed event (block 54019021).
// Keep `toBlock` safely below chain head — some RPCs reject ranges past the head.
export const SCENARIO_TO_BLOCK = BigInt(
  numOr(process.env.NEXT_PUBLIC_SCENARIO_TO_BLOCK, 54019100),
);

export const EXPLORER_URL = "https://sepolia.uniscan.xyz";
export const LASNA_EXPLORER_URL = "https://lasna.reactscan.net";

export function explorerAddress(addr: string): string {
  return `${EXPLORER_URL}/address/${addr}`;
}
export function explorerTx(hash: string): string {
  return `${EXPLORER_URL}/tx/${hash}`;
}
