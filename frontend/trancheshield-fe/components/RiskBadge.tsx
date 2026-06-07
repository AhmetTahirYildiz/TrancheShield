import type { CSSProperties } from "react";
import { riskMeta } from "@/lib/risk";

export function RiskBadge({
  mode,
  size = "md",
}: {
  mode: number;
  size?: "sm" | "md" | "lg";
}) {
  const meta = riskMeta(mode);
  const pad =
    size === "lg"
      ? "px-4 py-2 text-base"
      : size === "sm"
        ? "px-2 py-0.5 text-xs"
        : "px-3 py-1 text-sm";
  const ringColor =
    mode === 3
      ? "rgba(244,63,94,0.5)"
      : mode === 2
        ? "rgba(251,146,60,0.45)"
        : mode === 1
          ? "rgba(251,191,36,0.4)"
          : "rgba(52,211,153,0.4)";

  return (
    <span
      className={`inline-flex items-center gap-2 rounded-full border font-bold tracking-wider ${pad} ${meta.text} ${meta.border} ${meta.bg}`}
    >
      <span
        className={`pulse-dot inline-block rounded-full ${meta.dot} ${
          size === "lg" ? "h-2.5 w-2.5" : "h-2 w-2"
        }`}
        style={{ "--ring-color": ringColor } as CSSProperties}
      />
      {meta.label}
    </span>
  );
}
