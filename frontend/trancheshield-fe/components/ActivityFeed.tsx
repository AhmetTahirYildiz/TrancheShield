import { Card, CardHeader } from "@/components/ui";
import { explorerTx } from "@/lib/config";
import {
  bpsToMultiplier,
  bpsToPercent,
  formatTimestamp,
  riskMeta,
  shortenHex,
} from "@/lib/risk";
import type { ControlAction, FeedItem } from "@/hooks/useActivity";

const PARAM_LABEL: Record<string, string> = {
  riskMode: "Risk mode",
  feeMultiplier: "Fee multiplier",
  coverageRatio: "IL coverage",
  seniorDeposits: "Senior deposits",
};

function actionValue(a: ControlAction): { text: string; tone: string } {
  switch (a.parameter) {
    case "riskMode":
      return { text: riskMeta(Number(a.value)).label, tone: "text-rose-300" };
    case "feeMultiplier":
      return { text: bpsToMultiplier(a.value), tone: "text-amber-300" };
    case "coverageRatio":
      return { text: bpsToPercent(a.value), tone: "text-sky-300" };
    case "seniorDeposits":
      return {
        text: a.value === 1n ? "Enabled" : "Disabled",
        tone: a.value === 1n ? "text-emerald-300" : "text-rose-300",
      };
    default:
      return { text: a.value.toString(), tone: "text-zinc-200" };
  }
}

function Row({ item }: { item: FeedItem }) {
  const when = item.timestamp
    ? formatTimestamp(item.timestamp)
    : `block ${item.blockNumber}`;
  const av = item.kind === "action" ? actionValue(item) : null;

  return (
    <a
      href={explorerTx(item.txHash)}
      target="_blank"
      rel="noopener noreferrer"
      className="flex items-center justify-between gap-3 rounded-lg px-3 py-2.5 transition-colors hover:bg-white/[0.04]"
    >
      <div className="flex min-w-0 items-center gap-3">
        {item.kind === "swap" ? (
          <span className="inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-full border border-sky-500/30 bg-sky-500/10 text-sky-300">
            ⇄
          </span>
        ) : (
          <span className="inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-full border border-indigo-500/30 bg-indigo-500/10 text-indigo-300">
            ⚡
          </span>
        )}
        <div className="min-w-0">
          {item.kind === "swap" ? (
            <div className="text-sm text-zinc-200">
              Swap{" "}
              <span className="tabular text-zinc-500">
                Δtick {item.tickDelta}
              </span>
            </div>
          ) : (
            <div className="text-sm text-zinc-200">
              {PARAM_LABEL[item.parameter] ?? item.parameter} →{" "}
              <span className={`font-semibold ${av?.tone}`}>{av?.text}</span>
            </div>
          )}
          <div className="tabular truncate text-[11px] text-zinc-600">
            {when} · {shortenHex(item.txHash)}
          </div>
        </div>
      </div>
      <span className="shrink-0 text-[11px] uppercase tracking-wide text-zinc-600">
        {item.kind === "swap" ? "market" : "control"}
      </span>
    </a>
  );
}

export function ActivityFeed({
  feed,
  loading,
  error,
  rangeLabel,
}: {
  feed: FeedItem[];
  loading: boolean;
  error: string | null;
  rangeLabel: string;
}) {
  return (
    <Card className="flex h-full flex-col">
      <CardHeader
        title="Cross-chain activity"
        subtitle={rangeLabel ? `Scanning ${rangeLabel}` : undefined}
        right={
          <span className="text-xs text-zinc-500">{feed.length} events</span>
        }
      />
      <div className="flex-1 overflow-y-auto px-2 py-2" style={{ maxHeight: 360 }}>
        {error ? (
          <div className="px-3 py-6 text-center text-xs text-rose-300/80">
            Could not load logs in this range.
            <br />
            <span className="text-zinc-600">{error}</span>
          </div>
        ) : loading && feed.length === 0 ? (
          <div className="space-y-2 px-1">
            {Array.from({ length: 4 }).map((_, i) => (
              <div
                key={i}
                className="h-10 animate-pulse rounded-lg bg-white/[0.04]"
              />
            ))}
          </div>
        ) : feed.length === 0 ? (
          <div className="px-3 py-6 text-center text-sm text-zinc-600">
            No events in the scanned range
          </div>
        ) : (
          feed.map((item) => (
            <Row key={`${item.blockNumber}-${item.logIndex}`} item={item} />
          ))
        )}
      </div>
    </Card>
  );
}
