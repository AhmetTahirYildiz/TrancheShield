"use client";

import { Card } from "@/components/ui";
import { useRouterQuote } from "@/hooks/useRouterQuote";
import { explorerAddress, QUOTER_ADDRESS } from "@/lib/config";
import { formatToken, shortenHex } from "@/lib/risk";

export function RouterQuote() {
  const { amountIn, amountOut, gasEstimate, loading, error } = useRouterQuote();

  return (
    <Card className="px-5 py-3.5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <span className="text-[11px] font-medium uppercase tracking-wider text-zinc-500">
            Router quote
          </span>
          <span className="inline-flex items-center gap-1 rounded-full border border-sky-500/30 bg-sky-500/10 px-2 py-0.5 text-[10px] font-medium text-sky-300">
            Uniswap v4 Quoter
          </span>
        </div>

        {loading && amountOut === null ? (
          <div className="h-6 w-44 animate-pulse rounded bg-white/10" />
        ) : error || amountOut === null ? (
          <span className="text-xs text-zinc-600">quote unavailable</span>
        ) : (
          <div className="flex flex-wrap items-center gap-x-4 gap-y-1">
            <span className="tabular text-sm text-zinc-200">
              {formatToken(amountIn, 2)} token0
              <span className="mx-2 text-zinc-600">→</span>
              <span className="font-semibold text-sky-300">
                {formatToken(amountOut, 4)} token1
              </span>
            </span>
            {gasEstimate !== null && (
              <span className="tabular text-[11px] text-zinc-600">
                gas est. {gasEstimate.toLocaleString("en-US")}
              </span>
            )}
          </div>
        )}
      </div>

      <p className="mt-1.5 text-[11px] text-zinc-600">
        Exact-input quote routed through the hook by the official v4 Quoter (
        <a
          href={explorerAddress(QUOTER_ADDRESS)}
          target="_blank"
          rel="noopener noreferrer"
          className="text-zinc-500 underline-offset-2 hover:text-zinc-300 hover:underline"
        >
          {shortenHex(QUOTER_ADDRESS)}
        </a>
        ) — the hook adds a dynamic fee but no custom swap delta, so it&apos;s
        routable by standard infrastructure.
      </p>
    </Card>
  );
}
