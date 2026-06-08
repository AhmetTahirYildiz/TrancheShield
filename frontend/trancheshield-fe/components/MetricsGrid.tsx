import type { ReactNode } from "react";
import { Card } from "@/components/ui";
import { bpsToMultiplier, bpsToPercent, formatToken } from "@/lib/risk";
import type { RiskState } from "@/hooks/usePoolRiskState";

function Metric({
  label,
  value,
  hint,
  tone = "default",
  barPct,
  barColor = "bg-zinc-400",
}: {
  label: string;
  value: ReactNode;
  hint?: string;
  tone?: "default" | "good" | "warn" | "bad";
  barPct?: number;
  barColor?: string;
}) {
  const toneClass =
    tone === "good"
      ? "text-emerald-300"
      : tone === "warn"
        ? "text-amber-300"
        : tone === "bad"
          ? "text-rose-300"
          : "text-zinc-100";
  return (
    <Card className="px-4 py-3.5">
      <div className="text-[11px] font-medium uppercase tracking-wider text-zinc-500">
        {label}
      </div>
      <div className={`tabular mt-1.5 text-xl font-semibold ${toneClass}`}>
        {value}
      </div>
      {barPct !== undefined && (
        <div className="mt-2 h-1 w-full overflow-hidden rounded-full bg-white/[0.06]">
          <div
            className={`h-full rounded-full ${barColor}`}
            style={{ width: `${Math.max(0, Math.min(100, barPct))}%` }}
          />
        </div>
      )}
      {hint && <div className="mt-1 text-[11px] text-zinc-600">{hint}</div>}
    </Card>
  );
}

function MetricSkeleton() {
  return (
    <Card className="px-4 py-3.5">
      <div className="h-3 w-20 animate-pulse rounded bg-white/10" />
      <div className="mt-2 h-6 w-16 animate-pulse rounded bg-white/10" />
    </Card>
  );
}

export function MetricsGrid({ state }: { state: RiskState | null }) {
  if (!state) {
    return (
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
        {Array.from({ length: 5 }).map((_, i) => (
          <MetricSkeleton key={i} />
        ))}
      </div>
    );
  }

  const feeTone = state.feeMultiplierBps > 10_000n ? "warn" : "default";
  const covTone =
    state.coverageRatioBps >= 5_000n
      ? "good"
      : state.coverageRatioBps <= 1_000n
        ? "bad"
        : "warn";

  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
      <Metric
        label="Fee multiplier"
        value={bpsToMultiplier(state.feeMultiplierBps)}
        hint="on 0.30% base fee"
        tone={feeTone}
        barPct={((Number(state.feeMultiplierBps) - 10_000) / 20_000) * 100}
        barColor={feeTone === "warn" ? "bg-amber-400" : "bg-zinc-500"}
      />
      <Metric
        label="IL coverage"
        value={bpsToPercent(state.coverageRatioBps)}
        hint="of impermanent loss"
        tone={covTone}
        barPct={(Number(state.coverageRatioBps) / 5_000) * 100}
        barColor={
          covTone === "good"
            ? "bg-emerald-400"
            : covTone === "bad"
              ? "bg-rose-400"
              : "bg-amber-400"
        }
      />
      <Metric
        label="Senior deposits"
        value={state.seniorDepositsEnabled ? "Open" : "Halted"}
        tone={state.seniorDepositsEnabled ? "good" : "bad"}
      />
      <Metric
        label="Senior liability"
        value={formatToken(state.seniorLiability)}
        hint="token1 owed to Senior"
      />
      <Metric
        label="Junior collateral"
        value={formatToken(state.juniorCollateral)}
        hint="first-loss buffer"
      />
    </div>
  );
}
