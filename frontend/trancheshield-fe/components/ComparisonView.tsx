"use client";

import { useMemo, useState } from "react";
import { Card, CardHeader } from "@/components/ui";
import { RiskBadge } from "@/components/RiskBadge";
import { formatSignedUsd, formatUsd } from "@/lib/risk";
import {
  computeScenario,
  SCENARIOS,
  type PositionResult,
} from "@/lib/scenario";

function Line({
  label,
  value,
  show = true,
  tone = "neutral",
}: {
  label: string;
  value: string;
  show?: boolean;
  tone?: "neutral" | "pos" | "neg";
}) {
  const color =
    tone === "pos"
      ? "text-emerald-300"
      : tone === "neg"
        ? "text-rose-300"
        : "text-zinc-300";
  return (
    <div className="flex items-center justify-between py-1 text-xs">
      <span className="text-zinc-500">{label}</span>
      <span className={`tabular ${show ? color : "text-zinc-700"}`}>
        {show ? value : "—"}
      </span>
    </div>
  );
}

function Column({
  title,
  role,
  result,
  kind,
  barPct,
  highlight,
  badge,
}: {
  title: string;
  role: string;
  result: PositionResult;
  kind: "plain" | "senior" | "junior";
  barPct: number;
  highlight?: boolean;
  badge?: string;
}) {
  const barColor =
    kind === "senior"
      ? "bg-emerald-400"
      : kind === "junior"
        ? "bg-amber-400"
        : "bg-rose-400";
  const netColor =
    result.netVsHodl >= 0
      ? "text-emerald-300"
      : kind === "senior"
        ? "text-emerald-200"
        : "text-rose-300";

  return (
    <div
      className={`rounded-xl border p-4 ${
        highlight
          ? "border-emerald-500/40 bg-emerald-500/[0.04]"
          : "border-white/10 bg-white/[0.02]"
      }`}
    >
      <div className="flex items-start justify-between gap-2">
        <div>
          <div className="text-sm font-semibold text-zinc-100">{title}</div>
          <div className="text-[11px] text-zinc-500">{role}</div>
        </div>
        {badge && (
          <span className="rounded-md border border-emerald-500/40 bg-emerald-500/10 px-1.5 py-0.5 text-[10px] font-medium text-emerald-300">
            {badge}
          </span>
        )}
      </div>

      <div className="mt-3">
        <div className="text-[10px] uppercase tracking-wider text-zinc-500">
          Net vs HODL
        </div>
        <div className={`tabular text-2xl font-bold ${netColor}`}>
          {formatSignedUsd(result.netVsHodl)}
        </div>
        <div className="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-white/[0.06]">
          <div
            className={`h-full rounded-full ${barColor}`}
            style={{ width: `${barPct}%` }}
          />
        </div>
      </div>

      <div className="mt-3 border-t border-white/[0.06] pt-2">
        <Line label="Swap fees" value={formatSignedUsd(result.fees)} tone="pos" />
        <Line
          label="Insurance premium"
          value={formatSignedUsd(result.premium)}
          show={result.premium !== 0}
          tone={result.premium >= 0 ? "pos" : "neg"}
        />
        <Line
          label="IL compensation"
          value={formatSignedUsd(result.compensation)}
          show={result.compensation > 0}
          tone="pos"
        />
        <Line
          label="First-loss absorbed"
          value={formatSignedUsd(-result.juniorAbsorbed)}
          show={result.juniorAbsorbed > 0}
          tone="neg"
        />
      </div>
    </div>
  );
}

export function ComparisonView() {
  const [activeKey, setActiveKey] = useState(SCENARIOS[0].key);
  const scenario = useMemo(() => {
    const input = SCENARIOS.find((s) => s.key === activeKey) ?? SCENARIOS[0];
    return computeScenario(input);
  }, [activeKey]);

  const maxLoss = Math.max(
    Math.abs(scenario.plain.netVsHodl),
    Math.abs(scenario.senior.netVsHodl),
    Math.abs(scenario.junior.netVsHodl),
    1,
  );
  const bar = (n: number) => (Math.abs(n) / maxLoss) * 100;

  return (
    <Card>
      <CardHeader
        title="How it generalizes — modeled scenarios"
        subtitle="Deterministic projections from the same IL + waterfall logic, across market regimes (illustrative, not live data)"
        right={
          <div className="flex flex-wrap gap-1">
            {SCENARIOS.map((s) => (
              <button
                key={s.key}
                onClick={() => setActiveKey(s.key)}
                className={`rounded-full px-2.5 py-1 text-xs font-medium transition-colors ${
                  s.key === activeKey
                    ? "bg-white/10 text-white"
                    : "text-zinc-500 hover:text-zinc-300"
                }`}
              >
                {s.label}
              </button>
            ))}
          </div>
        }
      />

      <div className="px-5 py-4">
        {/* Scenario facts (shared across all three LPs) */}
        <div className="flex flex-wrap items-center gap-x-6 gap-y-2 rounded-xl border border-white/10 bg-white/[0.02] px-4 py-3 text-xs">
          <div className="flex items-center gap-2">
            <span className="text-zinc-500">Regime</span>
            <RiskBadge mode={scenario.input.regime} size="sm" />
          </div>
          <Fact label="Price move" value={`${scenario.priceMovePct >= 0 ? "+" : ""}${scenario.priceMovePct.toFixed(0)}%`} />
          <Fact label="Position value" value={formatUsd(scenario.v0)} />
          <Fact label="HODL value" value={formatUsd(scenario.plain.hodl)} />
          <Fact label="LP exit value" value={formatUsd(scenario.plain.lpValue)} />
          <Fact
            label="Impermanent loss"
            value={`${formatUsd(scenario.il)} (${scenario.ilPct.toFixed(1)}%)`}
            tone="neg"
          />
        </div>

        {/* Headline */}
        <div className="mt-4 rounded-xl border border-emerald-500/30 bg-emerald-500/[0.06] px-4 py-3">
          <span className="text-sm text-emerald-200">
            <span className="font-bold">
              Senior LP lost {scenario.seniorSavingPct.toFixed(0)}% less
            </span>{" "}
            than an unprotected LP in this scenario —{" "}
            <span className="tabular font-semibold">
              {formatUsd(scenario.seniorSavingAbs)}
            </span>{" "}
            recovered via IL compensation.
          </span>
        </div>

        {/* Three columns */}
        <div className="mt-4 grid grid-cols-1 gap-3 md:grid-cols-3">
          <Column
            title="Unprotected LP"
            role="Plain Uniswap v4 LP"
            result={scenario.plain}
            kind="plain"
            barPct={bar(scenario.plain.netVsHodl)}
          />
          <Column
            title="TrancheShield · Senior"
            role="Pays premium · IL protected"
            result={scenario.senior}
            kind="senior"
            barPct={bar(scenario.senior.netVsHodl)}
            highlight
            badge="BEST DOWNSIDE"
          />
          <Column
            title="TrancheShield · Junior"
            role="Earns premium · first-loss"
            result={scenario.junior}
            kind="junior"
            barPct={bar(scenario.junior.netVsHodl)}
          />
        </div>

        <p className="mt-3 text-[11px] leading-relaxed text-zinc-600">
          All three hold the same LP position and take the same impermanent loss.
          The Senior tranche diverts a slice of swap yield as an insurance premium
          and receives bounded IL compensation; the Junior tranche earns that
          premium and backstops the reserve as first-loss capital.
        </p>
      </div>
    </Card>
  );
}

function Fact({
  label,
  value,
  tone = "neutral",
}: {
  label: string;
  value: string;
  tone?: "neutral" | "neg";
}) {
  return (
    <div className="flex items-center gap-2">
      <span className="text-zinc-500">{label}</span>
      <span
        className={`tabular font-medium ${tone === "neg" ? "text-rose-300" : "text-zinc-200"}`}
      >
        {value}
      </span>
    </div>
  );
}
