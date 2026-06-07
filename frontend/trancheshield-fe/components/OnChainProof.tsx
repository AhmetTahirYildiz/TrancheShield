"use client";

import { Card } from "@/components/ui";
import { useOnChainProof } from "@/hooks/useOnChainProof";
import { explorerTx } from "@/lib/config";
import { formatToken, shortenHex } from "@/lib/risk";

function tok(wei: bigint): string {
  return formatToken(wei, 3);
}

export function OnChainProof() {
  const { proof, loading, error } = useOnChainProof();

  const remaining =
    proof && proof.ilShortfall > proof.compensation
      ? proof.ilShortfall - proof.compensation
      : 0n;
  const recoveryPct = proof ? (proof.recoveryBps / 100).toFixed(0) : "0";

  // Bars relative to the (larger) unprotected loss.
  const unprotectedPct = 100;
  const seniorPct = proof && proof.ilShortfall > 0n
    ? Number((remaining * 100n) / proof.ilShortfall)
    : 0;

  return (
    <Card className="overflow-hidden border-emerald-500/20">
      <div className="flex flex-wrap items-start justify-between gap-3 border-b border-white/[0.06] px-5 pt-4 pb-3">
        <div>
          <div className="flex items-center gap-2">
            <h2 className="text-sm font-semibold tracking-wide text-zinc-100">
              Live IL protection — verified on-chain
            </h2>
            <span className="inline-flex items-center gap-1 rounded-full border border-emerald-500/40 bg-emerald-500/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-emerald-300">
              <span className="h-1.5 w-1.5 rounded-full bg-emerald-400" />
              On-chain
            </span>
          </div>
          <p className="mt-0.5 text-xs text-zinc-500">
            A real Senior LP that took impermanent loss and received compensation
            from the hook — read from the live PositionClosed event.
          </p>
        </div>
        {proof && (
          <a
            href={explorerTx(proof.txHash)}
            target="_blank"
            rel="noopener noreferrer"
            className="tabular shrink-0 rounded-full border border-white/10 bg-white/[0.03] px-3 py-1 text-xs text-zinc-300 transition-colors hover:border-white/20 hover:text-white"
          >
            tx {shortenHex(proof.txHash)} ↗
          </a>
        )}
      </div>

      <div className="px-5 py-4">
        {loading && !proof ? (
          <div className="h-28 animate-pulse rounded-xl bg-white/[0.04]" />
        ) : error || !proof ? (
          <div className="py-6 text-center text-sm text-zinc-600">
            {error
              ? `Could not read the on-chain proof: ${error}`
              : "On-chain scenario not found in the configured block window."}
          </div>
        ) : (
          <>
            {/* Headline */}
            <div className="rounded-xl border border-emerald-500/30 bg-emerald-500/[0.06] px-4 py-3">
              <span className="text-sm text-emerald-200">
                <span className="font-bold">
                  Senior LP recovered {recoveryPct}% of its impermanent loss
                </span>{" "}
                — the hook computed{" "}
                <span className="tabular font-semibold">{tok(proof.ilShortfall)}</span>{" "}
                IL and booked{" "}
                <span className="tabular font-semibold">{tok(proof.compensation)}</span>{" "}
                token1 of compensation, on-chain.
              </span>
            </div>

            {/* Stats */}
            <div className="mt-4 grid grid-cols-3 gap-3">
              <Stat label="Impermanent loss" value={tok(proof.ilShortfall)} unit="token1" tone="neg" />
              <Stat label="Compensation" value={tok(proof.compensation)} unit="token1" tone="pos" />
              <Stat label="Recovery" value={`${recoveryPct}%`} unit="of IL" tone="pos" />
            </div>

            {/* Two-way real comparison */}
            <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2">
              <Outcome
                title="Unprotected LP"
                role="No coverage — takes the full IL"
                net={`-${tok(proof.ilShortfall)}`}
                barPct={unprotectedPct}
                barColor="bg-rose-400"
                netColor="text-rose-300"
              />
              <Outcome
                title="TrancheShield · Senior"
                role="IL compensated by the Junior tranche"
                net={`-${tok(remaining)}`}
                barPct={seniorPct}
                barColor="bg-emerald-400"
                netColor="text-emerald-200"
                highlight
              />
            </div>

            <p className="mt-3 text-[11px] leading-relaxed text-zinc-600">
              Real values from poolId {shortenHex("0x0fe678433179b93a0b6f4ced6c23ad08413ccc7b657e292e3dc925518af6cbb9")}.
              The reserve was empty, so compensation was drawn from the Junior
              tranche (Tier 2 of the waterfall) — the Junior collateral was
              decremented on-chain to cover the Senior&apos;s loss. Token-level
              settlement of the Tier-2 draw is bookkeeping in this MVP; the Tier-1
              reserve path transfers tokens directly.
            </p>
          </>
        )}
      </div>
    </Card>
  );
}

function Stat({
  label,
  value,
  unit,
  tone,
}: {
  label: string;
  value: string;
  unit: string;
  tone: "pos" | "neg" | "neutral";
}) {
  const color =
    tone === "pos" ? "text-emerald-300" : tone === "neg" ? "text-rose-300" : "text-zinc-100";
  return (
    <div className="rounded-xl border border-white/10 bg-white/[0.02] px-4 py-3">
      <div className="text-[11px] uppercase tracking-wider text-zinc-500">{label}</div>
      <div className={`tabular mt-1 text-xl font-semibold ${color}`}>{value}</div>
      <div className="text-[11px] text-zinc-600">{unit}</div>
    </div>
  );
}

function Outcome({
  title,
  role,
  net,
  barPct,
  barColor,
  netColor,
  highlight,
}: {
  title: string;
  role: string;
  net: string;
  barPct: number;
  barColor: string;
  netColor: string;
  highlight?: boolean;
}) {
  return (
    <div
      className={`rounded-xl border p-4 ${
        highlight ? "border-emerald-500/40 bg-emerald-500/[0.04]" : "border-white/10 bg-white/[0.02]"
      }`}
    >
      <div className="text-sm font-semibold text-zinc-100">{title}</div>
      <div className="text-[11px] text-zinc-500">{role}</div>
      <div className="mt-2 text-[10px] uppercase tracking-wider text-zinc-500">Net vs HODL</div>
      <div className={`tabular text-2xl font-bold ${netColor}`}>{net}</div>
      <div className="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-white/[0.06]">
        <div className={`h-full rounded-full ${barColor}`} style={{ width: `${barPct}%` }} />
      </div>
    </div>
  );
}
