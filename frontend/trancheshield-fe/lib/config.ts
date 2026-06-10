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
  "0x8E82Bea6010325cc9107331B2842FCD3D14e034a",
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

// ---------------------------------------------------------------------------
// Interactive demo pool (script/SeedInteractivePool.s.sol) — a FRESH pool that
// starts LOW so judges can drive swaps from the UI and watch it flip to CRISIS.
// ---------------------------------------------------------------------------
export const INTERACTIVE_POOL_ID = envOr(
  process.env.NEXT_PUBLIC_INTERACTIVE_POOL_ID,
  "0x863ae83865d5e214660cad63d93c6f84279137c9fb4ad91f4ee97aecae4f9e5e",
) as Hex;
export const INTERACTIVE_TOKEN0 = envOr(
  process.env.NEXT_PUBLIC_INTERACTIVE_TOKEN0,
  "0x1363436d53e895207d2c3778f3675c321babb913",
).toLowerCase() as Address;
export const INTERACTIVE_TOKEN1 = envOr(
  process.env.NEXT_PUBLIC_INTERACTIVE_TOKEN1,
  "0xb5df790f62d841ea404bef0e2ac592c063792d6b",
).toLowerCase() as Address;

/** v4 test routers on Unichain Sepolia (used by the interactive actions). */
export const MODIFY_ROUTER = "0x5fa728C0A5cfd51BEe4B060773f50554c0C8A7AB" as Address;
export const SWAP_ROUTER = "0x9140a78c1A137c7fF1c151EC8231272aF78a99A4" as Address;

/** Full-range ticks for tickSpacing 60, and the zeroForOne price-limit floor. */
export const FULL_RANGE_TICK_LOWER = -120000;
export const FULL_RANGE_TICK_UPPER = 120000;
export const MIN_SQRT_PRICE_LIMIT = 4295128740n;
export const MAX_UINT256 =
  115792089237316195423570985008687907853269984665640564039457584007913129639935n;

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

/**
 * The exact transaction that produced the PositionClosed proof
 * (script/RealComparison.s.sol — Senior withdrawal with real IL + compensation).
 * The OnChainProof reads this receipt BY HASH rather than via eth_getLogs over a
 * block range: the event sits ~150k+ blocks back, past the window many public
 * RPCs serve for getLogs, but a known hash resolves through getTransactionReceipt
 * regardless — so the proof never "ages out" of view.
 */
export const SCENARIO_TX_HASH = envOr(
  process.env.NEXT_PUBLIC_SCENARIO_TX_HASH,
  "0x41f83c694e25cf8459e470dde3b519cfa8b419f9e1daeb14cc3ff383cdff59ed",
) as Hex;

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
