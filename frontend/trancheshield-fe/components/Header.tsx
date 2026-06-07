import type { CSSProperties } from "react";
import { Chip } from "@/components/ui";
import {
  explorerAddress,
  HOOK_ADDRESS,
  LASNA_EXPLORER_URL,
  POOL_ID,
  RECEIVER_ADDRESS,
  RSC_ADDRESS,
} from "@/lib/config";
import { shortenHex } from "@/lib/risk";

function AddrChip({
  label,
  addr,
  href,
  dot,
}: {
  label: string;
  addr: string;
  href: string;
  dot: string;
}) {
  return (
    <a href={href} target="_blank" rel="noopener noreferrer">
      <Chip className="border-white/10 bg-white/[0.03] text-zinc-300 hover:border-white/20 hover:text-white">
        <span className={`h-1.5 w-1.5 rounded-full ${dot}`} />
        <span className="text-zinc-500">{label}</span>
        <span className="tabular">{shortenHex(addr)}</span>
      </Chip>
    </a>
  );
}

export function Header({
  live,
  lastUpdatedLabel,
  onRefresh,
}: {
  live: boolean;
  lastUpdatedLabel: string;
  onRefresh: () => void;
}) {
  return (
    <header className="flex flex-col gap-4">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <div className="flex items-center gap-2.5">
            <span className="inline-flex h-8 w-8 items-center justify-center rounded-lg border border-sky-400/30 bg-sky-400/10 text-sky-300">
              🛡
            </span>
            <h1 className="text-xl font-semibold tracking-tight text-white">
              TrancheShield
            </h1>
            <span className="rounded-md border border-white/10 bg-white/[0.03] px-2 py-0.5 text-[11px] text-zinc-400">
              Risk Console
            </span>
          </div>
          <p className="mt-1.5 max-w-xl text-sm text-zinc-500">
            A Uniswap v4 IL-protection hook governed by a cross-chain Reactive
            Network controller. Volatility on Unichain drives the risk regime
            from Lasna — live.
          </p>
        </div>

        <div className="flex flex-col items-end gap-2">
          <div className="flex items-center gap-2">
            <span
              className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium ${
                live
                  ? "border-emerald-500/40 bg-emerald-500/10 text-emerald-300"
                  : "border-zinc-600/40 bg-zinc-600/10 text-zinc-400"
              }`}
            >
              <span
                className={`h-1.5 w-1.5 rounded-full ${live ? "bg-emerald-400 pulse-dot" : "bg-zinc-500"}`}
                style={
                  { "--ring-color": "rgba(52,211,153,0.5)" } as CSSProperties
                }
              />
              {live ? "Live" : "Connecting"}
            </span>
            <button
              onClick={onRefresh}
              className="rounded-full border border-white/10 bg-white/[0.03] px-3 py-1 text-xs text-zinc-300 transition-colors hover:border-white/20 hover:text-white"
            >
              Refresh
            </button>
          </div>
          <div className="tabular text-[11px] text-zinc-600">
            {lastUpdatedLabel}
          </div>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <AddrChip
          label="Hook"
          addr={HOOK_ADDRESS}
          href={explorerAddress(HOOK_ADDRESS)}
          dot="bg-sky-400"
        />
        <AddrChip
          label="Receiver"
          addr={RECEIVER_ADDRESS}
          href={explorerAddress(RECEIVER_ADDRESS)}
          dot="bg-emerald-400"
        />
        <AddrChip
          label="RSC · Lasna"
          addr={RSC_ADDRESS}
          href={`${LASNA_EXPLORER_URL}/address/${RSC_ADDRESS}`}
          dot="bg-indigo-400"
        />
        <Chip className="border-white/10 bg-white/[0.03] text-zinc-400">
          <span className="text-zinc-500">Pool</span>
          <span className="tabular">{shortenHex(POOL_ID)}</span>
        </Chip>
      </div>
    </header>
  );
}
