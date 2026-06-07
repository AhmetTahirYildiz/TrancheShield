import type { ReactNode } from "react";

export function Card({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={`rounded-2xl border border-white/10 bg-white/[0.03] backdrop-blur-sm shadow-[0_1px_0_0_rgba(255,255,255,0.04)_inset] ${className}`}
    >
      {children}
    </div>
  );
}

export function CardHeader({
  title,
  subtitle,
  right,
}: {
  title: string;
  subtitle?: string;
  right?: ReactNode;
}) {
  return (
    <div className="flex items-start justify-between gap-3 px-5 pt-4 pb-3 border-b border-white/[0.06]">
      <div>
        <h2 className="text-sm font-semibold tracking-wide text-zinc-100">
          {title}
        </h2>
        {subtitle && (
          <p className="mt-0.5 text-xs text-zinc-500">{subtitle}</p>
        )}
      </div>
      {right}
    </div>
  );
}

export function Chip({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium ${className}`}
    >
      {children}
    </span>
  );
}
