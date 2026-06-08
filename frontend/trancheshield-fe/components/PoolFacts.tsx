import { Card } from "@/components/ui";
import { relativeTime } from "@/lib/risk";
import type { RiskState } from "@/hooks/usePoolRiskState";
import type { VolatilityPoint } from "@/hooks/useActivity";

const BASE_FEE_PCT = 0.3; // 3000 pips = 0.30% at multiplier 1.00x

function Fact({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="flex min-w-[120px] flex-col">
      <span className="text-[11px] uppercase tracking-wider text-zinc-500">
        {label}
      </span>
      <span className="tabular text-base font-semibold text-zinc-100">{value}</span>
      {sub && <span className="tabular text-[11px] text-zinc-600">{sub}</span>}
    </div>
  );
}

/**
 * A thin "pool facts" strip derived entirely from data we already poll — the
 * risk state and the latest observed swap. No extra contract reads.
 */
export function PoolFacts({
  state,
  volatility,
}: {
  state: RiskState | null;
  volatility: VolatilityPoint[];
}) {
  const last = volatility.length ? volatility[volatility.length - 1] : null;
  const tick = last ? last.tickAfter : null;
  const price = tick !== null ? Math.pow(1.0001, tick) : null;
  const feePct = state
    ? (BASE_FEE_PCT * Number(state.feeMultiplierBps)) / 10_000
    : null;

  return (
    <Card className="px-5 py-3.5">
      <div className="flex flex-wrap items-center gap-x-8 gap-y-3">
        <Fact
          label="Current fee"
          value={feePct !== null ? `${feePct.toFixed(2)}%` : "—"}
          sub={
            state ? `${(Number(state.feeMultiplierBps) / 10_000).toFixed(2)}x base` : undefined
          }
        />
        <Fact
          label="Latest tick"
          value={tick !== null ? tick.toLocaleString("en-US") : "—"}
          sub="last observed swap"
        />
        <Fact
          label="Price (t1/t0)"
          value={price !== null ? price.toFixed(price < 1 ? 4 : 3) : "—"}
        />
        <Fact
          label="Last swap"
          value={last ? relativeTime(last.timestamp) : "—"}
        />
        <Fact
          label="Observed swaps"
          value={volatility.length.toString()}
        />
      </div>
    </Card>
  );
}
