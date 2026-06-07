"use client";

import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { Card, CardHeader } from "@/components/ui";
import type { VolatilityPoint } from "@/hooks/useActivity";

interface TooltipEntry {
  payload: VolatilityPoint;
}

function ChartTooltip({
  active,
  payload,
}: {
  active?: boolean;
  payload?: TooltipEntry[];
}) {
  if (!active || !payload?.length) return null;
  const p = payload[0].payload;
  return (
    <div className="rounded-lg border border-white/10 bg-[#0b1220] px-3 py-2 text-xs shadow-xl">
      <div className="tabular text-zinc-300">
        Δtick <span className="font-semibold text-sky-300">{p.tickDelta}</span>
      </div>
      <div className="tabular mt-0.5 text-zinc-500">
        swap #{p.index} · block {p.block}
      </div>
    </div>
  );
}

export function VolatilityChart({ data }: { data: VolatilityPoint[] }) {
  return (
    <Card>
      <CardHeader
        title="Realized volatility"
        subtitle="Per-swap tick movement (|Δtick|) — the signal driving the RSC"
        right={
          <span className="text-xs text-zinc-500">
            {data.length} swap{data.length === 1 ? "" : "s"}
          </span>
        }
      />
      <div className="h-56 px-2 py-3">
        {data.length === 0 ? (
          <div className="flex h-full items-center justify-center text-sm text-zinc-600">
            No swaps in the scanned range
          </div>
        ) : (
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={data} margin={{ top: 8, right: 12, left: -8, bottom: 0 }}>
              <defs>
                <linearGradient id="volFill" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="#38bdf8" stopOpacity={0.5} />
                  <stop offset="100%" stopColor="#38bdf8" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.05)" />
              <XAxis
                dataKey="index"
                tick={{ fill: "#52607a", fontSize: 11 }}
                axisLine={{ stroke: "rgba(255,255,255,0.08)" }}
                tickLine={false}
              />
              <YAxis
                tick={{ fill: "#52607a", fontSize: 11 }}
                axisLine={false}
                tickLine={false}
                width={44}
                tickFormatter={(v: number) =>
                  v >= 1000 ? `${(v / 1000).toFixed(1)}k` : `${v}`
                }
              />
              <Tooltip content={<ChartTooltip />} cursor={{ stroke: "rgba(255,255,255,0.1)" }} />
              <Area
                type="monotone"
                dataKey="tickDelta"
                stroke="#38bdf8"
                strokeWidth={2}
                fill="url(#volFill)"
                isAnimationActive={false}
                dot={{ r: 2, fill: "#38bdf8" }}
              />
            </AreaChart>
          </ResponsiveContainer>
        )}
      </div>
    </Card>
  );
}
