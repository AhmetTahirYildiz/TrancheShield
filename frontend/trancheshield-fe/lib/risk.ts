import { formatUnits } from "viem";

/** RiskMode enum — mirrors ITrancheShieldHook.RiskMode (LOW..CRISIS). */
export type RiskModeIndex = 0 | 1 | 2 | 3;

export interface RiskModeMeta {
  label: string;
  blurb: string;
  /** Tailwind text/border/bg accent classes for this regime. */
  text: string;
  border: string;
  bg: string;
  dot: string;
}

export const RISK_MODES: Record<RiskModeIndex, RiskModeMeta> = {
  0: {
    label: "LOW",
    blurb: "Calm market. Base fees, full coverage offered, Senior deposits open.",
    text: "text-emerald-300",
    border: "border-emerald-500/40",
    bg: "bg-emerald-500/10",
    dot: "bg-emerald-400",
  },
  1: {
    label: "MEDIUM",
    blurb: "Volatility building. Fees lifting, coverage trimming.",
    text: "text-amber-300",
    border: "border-amber-500/40",
    bg: "bg-amber-500/10",
    dot: "bg-amber-400",
  },
  2: {
    label: "HIGH",
    blurb: "Stress. Fees elevated, coverage reduced, reserve defending.",
    text: "text-orange-300",
    border: "border-orange-500/40",
    bg: "bg-orange-500/10",
    dot: "bg-orange-400",
  },
  3: {
    label: "CRISIS",
    blurb: "Bank-run / crash regime. Senior deposits halted, coverage floored.",
    text: "text-rose-300",
    border: "border-rose-500/50",
    bg: "bg-rose-500/10",
    dot: "bg-rose-400",
  },
};

export function riskMeta(mode: number): RiskModeMeta {
  return RISK_MODES[(Math.min(Math.max(mode, 0), 3) as RiskModeIndex)];
}

/** feeMultiplierBps where 10_000 = 1.00x. */
export function bpsToMultiplier(bps: bigint): string {
  return `${(Number(bps) / 10_000).toFixed(2)}x`;
}

/** coverageRatioBps where 10_000 = 100%, 5_000 = 50%. */
export function bpsToPercent(bps: bigint): string {
  return `${(Number(bps) / 100).toFixed(bps % 100n === 0n ? 0 : 1)}%`;
}

/** 18-decimal token amount → compact human string (e.g. 99.75, 2.02k). */
export function formatToken(wei: bigint, maxFrac = 2): string {
  const n = Number(formatUnits(wei, 18));
  if (n === 0) return "0";
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(2)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(2)}k`;
  return n.toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: maxFrac,
  });
}

/** Signed USD with a +/- sign, e.g. "-$311.60", "+$170.80". */
export function formatSignedUsd(n: number, frac = 2): string {
  const sign = n < 0 ? "-" : "+";
  return `${sign}$${Math.abs(n).toLocaleString("en-US", {
    minimumFractionDigits: frac,
    maximumFractionDigits: frac,
  })}`;
}

/** Plain USD, no forced sign, e.g. "$13,500". */
export function formatUsd(n: number, frac = 0): string {
  return `$${n.toLocaleString("en-US", {
    minimumFractionDigits: frac,
    maximumFractionDigits: frac,
  })}`;
}

export function shortenHex(hex: string, lead = 6, tail = 4): string {
  if (hex.length <= lead + tail + 2) return hex;
  return `${hex.slice(0, lead)}…${hex.slice(-tail)}`;
}

export function formatTimestamp(unix: bigint | number): string {
  const ms = Number(unix) * 1000;
  if (!ms) return "—";
  return new Date(ms).toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

export function relativeTime(unix: bigint | number): string {
  const secs = Math.floor(Date.now() / 1000) - Number(unix);
  if (secs < 0 || !Number.isFinite(secs)) return "—";
  if (secs < 60) return `${secs}s ago`;
  if (secs < 3600) return `${Math.floor(secs / 60)}m ago`;
  if (secs < 86400) return `${Math.floor(secs / 3600)}h ago`;
  return `${Math.floor(secs / 86400)}d ago`;
}
