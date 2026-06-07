import type { ReactNode } from "react";
import { Card } from "@/components/ui";
import { bpsToMultiplier, bpsToPercent, formatToken } from "@/lib/risk";
import type { RiskState } from "@/hooks/usePoolRiskState";

function Metric({
  label,
  value,
  hint,
  tone = "default",
}: {
  label: string;
  value: ReactNode;
  hint?: string;
  tone?: "default" | "good" | "warn" | "bad";
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
      {hint && <div className="mt-0.5 text-[11px] text-zinc-600">{hint}</div>}
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
      />
      <Metric
        label="IL coverage"
        value={bpsToPercent(state.coverageRatioBps)}
        hint="of impermanent loss"
        tone={covTone}
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
