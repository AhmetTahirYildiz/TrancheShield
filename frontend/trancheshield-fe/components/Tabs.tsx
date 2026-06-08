export interface TabDef {
  key: string;
  label: string;
}

export function Tabs({
  tabs,
  active,
  onChange,
}: {
  tabs: TabDef[];
  active: string;
  onChange: (key: string) => void;
}) {
  return (
    <div className="inline-flex gap-1 rounded-xl border border-white/10 bg-white/[0.02] p-1">
      {tabs.map((t) => {
        const isActive = t.key === active;
        return (
          <button
            key={t.key}
            onClick={() => onChange(t.key)}
            className={`rounded-lg px-4 py-1.5 text-sm font-medium transition-colors ${
              isActive
                ? "bg-white/10 text-white shadow-[0_1px_0_0_rgba(255,255,255,0.06)_inset]"
                : "text-zinc-500 hover:text-zinc-300"
            }`}
          >
            {t.label}
          </button>
        );
      })}
    </div>
  );
}
