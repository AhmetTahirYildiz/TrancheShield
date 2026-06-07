import type { ReactNode } from "react";

function Stage({
  chain,
  title,
  desc,
  accent,
}: {
  chain: string;
  title: string;
  desc: string;
  accent: string;
}) {
  return (
    <div className="flex-1 min-w-[150px] rounded-xl border border-white/10 bg-white/[0.02] px-4 py-3">
      <div className={`text-[10px] font-semibold uppercase tracking-widest ${accent}`}>
        {chain}
      </div>
      <div className="mt-1 text-sm font-semibold text-zinc-100">{title}</div>
      <div className="mt-0.5 text-xs leading-snug text-zinc-500">{desc}</div>
    </div>
  );
}

function Arrow({ children }: { children?: ReactNode }) {
  return (
    <div className="flex shrink-0 flex-col items-center justify-center px-1 text-zinc-600">
      <span className="text-lg leading-none">→</span>
      {children && <span className="mt-0.5 text-[9px] text-zinc-600">{children}</span>}
    </div>
  );
}

/**
 * The cross-chain control loop — the project's core differentiator. A swap on
 * Unichain feeds the Reactive Smart Contract on Lasna, which reacts and calls
 * back into the hook with bounded risk-parameter updates.
 */
export function FlowStrip() {
  return (
    <div className="flex flex-wrap items-stretch gap-1">
      <Stage
        chain="Unichain Sepolia"
        title="Swap activity"
        desc="Hook emits SwapRiskObserved on every swap"
        accent="text-sky-300"
      />
      <Arrow>subscribe</Arrow>
      <Stage
        chain="Lasna · Reactive"
        title="RSC react()"
        desc="Welford volatility → derives risk regime"
        accent="text-indigo-300"
      />
      <Arrow>callback</Arrow>
      <Stage
        chain="Unichain Sepolia"
        title="Receiver → Hook"
        desc="Bounded setRiskMode / fee / coverage"
        accent="text-emerald-300"
      />
    </div>
  );
}
