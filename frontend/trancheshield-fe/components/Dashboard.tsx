"use client";

import { useCallback, useEffect, useState } from "react";
import { usePoolRiskState } from "@/hooks/usePoolRiskState";
import { useActivity } from "@/hooks/useActivity";
import { Header } from "@/components/Header";
import { Tabs } from "@/components/Tabs";
import { StatusCard } from "@/components/StatusCard";
import { PoolFacts } from "@/components/PoolFacts";
import { RouterQuote } from "@/components/RouterQuote";
import { MetricsGrid } from "@/components/MetricsGrid";
import { OnChainProof } from "@/components/OnChainProof";
import { ComparisonView } from "@/components/ComparisonView";
import { VolatilityChart } from "@/components/VolatilityChart";
import { ActivityFeed } from "@/components/ActivityFeed";

export function Dashboard() {
  const risk = usePoolRiskState();
  const activity = useActivity();
  const [now, setNow] = useState(() => Date.now());
  const [tab, setTab] = useState("live");

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);

  const refreshAll = useCallback(() => {
    risk.refetch();
    activity.refetch();
  }, [risk, activity]);

  const live = !risk.error && risk.state !== null;
  const lastUpdatedLabel = risk.fetchedAt
    ? `Updated ${Math.max(0, Math.round((now - risk.fetchedAt) / 1000))}s ago`
    : "Awaiting first read…";

  return (
    <main className="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6 lg:py-10">
      <Header
        live={live}
        lastUpdatedLabel={lastUpdatedLabel}
        onRefresh={refreshAll}
      />

      <div className="mt-6">
        <Tabs
          tabs={[
            { key: "live", label: "Live Risk" },
            { key: "protection", label: "IL Protection" },
          ]}
          active={tab}
          onChange={setTab}
        />
      </div>

      <div className="mt-5 flex flex-col gap-5">
        {tab === "live" && (
          <>
            <StatusCard
              state={risk.state}
              loading={risk.loading}
              error={risk.error}
            />

            <PoolFacts state={risk.state} volatility={activity.volatility} />

            <RouterQuote />

            <MetricsGrid state={risk.state} />

            <div className="grid grid-cols-1 gap-5 lg:grid-cols-3">
              <div className="lg:col-span-2">
                <VolatilityChart data={activity.volatility} />
              </div>
              <div className="lg:col-span-1">
                <ActivityFeed
                  feed={activity.feed}
                  loading={activity.loading}
                  error={activity.error}
                  rangeLabel={activity.rangeLabel}
                />
              </div>
            </div>
          </>
        )}

        {tab === "protection" && (
          <>
            <OnChainProof />

            <ComparisonView />
          </>
        )}
      </div>

      <footer className="mt-10 border-t border-white/[0.06] pt-5 text-xs text-zinc-600">
        Read-only dashboard · Unichain Sepolia (1301) ↔ Reactive Lasna (5318007).
        Risk parameters are written on-chain only by the Reactive controller via
        bounded callbacks.
      </footer>
    </main>
  );
}
