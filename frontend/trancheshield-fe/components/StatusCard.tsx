import { Card } from "@/components/ui";
import { RiskBadge } from "@/components/RiskBadge";
import { FlowStrip } from "@/components/FlowStrip";
import { riskMeta, formatTimestamp, relativeTime } from "@/lib/risk";
import type { RiskState } from "@/hooks/usePoolRiskState";

export function StatusCard({
  state,
  loading,
  error,
}: {
  state: RiskState | null;
  loading: boolean;
  error: string | null;
}) {
  const mode = state ? state.mode : 0;
  const meta = riskMeta(mode);

  return (
    <Card className="overflow-hidden">
      <div className="relative px-6 py-6">
        <div
          className={`pointer-events-none absolute inset-0 opacity-[0.15] ${meta.bg}`}
        />
        <div className="relative flex flex-col gap-5">
          <div className="flex flex-wrap items-center justify-between gap-4">
            <div>
              <div className="text-xs font-medium uppercase tracking-widest text-zinc-500">
                Pool risk regime
              </div>
              <div className="mt-2 flex items-center gap-3">
                {loading && !state ? (
                  <div className="h-9 w-32 animate-pulse rounded-full bg-white/10" />
                ) : (
                  <RiskBadge mode={mode} size="lg" />
                )}
              </div>
              <p className={`mt-2 max-w-md text-sm ${meta.text}`}>{meta.blurb}</p>
            </div>

            <div className="text-right">
              {state?.lastRiskUpdate ? (
                <>
                  <div className="text-xs text-zinc-500">Last risk update</div>
                  <div className="tabular mt-1 text-sm text-zinc-200">
                    {relativeTime(state.lastRiskUpdate)}
                  </div>
                  <div className="tabular text-[11px] text-zinc-600">
                    {formatTimestamp(state.lastRiskUpdate)}
                  </div>
                </>
              ) : (
                <div className="text-xs text-zinc-600">No update yet</div>
              )}
              {!state?.seniorDepositsEnabled && state && (
                <div className="mt-2 inline-flex rounded-md border border-rose-500/40 bg-rose-500/10 px-2 py-0.5 text-[11px] font-medium text-rose-300">
                  Senior deposits halted
                </div>
              )}
            </div>
          </div>

          <FlowStrip />

          {error && (
            <div className="rounded-lg border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-xs text-rose-300">
              RPC read error: {error}
            </div>
          )}
        </div>
      </div>
    </Card>
  );
}
