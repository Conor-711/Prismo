import { LocaleLink } from "./i18n/LocaleLink";
import { getMindshare } from "@/lib/queries";

// 顶部信号条：top ticker 的情绪 tape（绿/红，像真实行情走马灯）。纯 CSS 滚动。
export function TickerTape() {
  const rows = getMindshare(22);
  if (!rows.length) return null;

  const items = rows.map((r) => ({ ticker: r.ticker, s: r.sentiment }));
  const loop = [...items, ...items]; // 复制一份实现无缝循环

  return (
    <div className="tape-mask relative border-b border-line bg-surface/40 overflow-hidden h-9 hidden sm:block">
      <div className="tape-track h-9 items-center">
        {loop.map((t, i) => {
          const up = t.s > 0.05;
          const down = t.s < -0.05;
          const color = up ? "#24B47E" : down ? "#F0556E" : "#8A8A93";
          return (
            <LocaleLink
              key={i}
              href={`/ticker/${t.ticker}`}
              className="inline-flex items-center gap-1.5 px-3.5 border-l border-white/[.05] hover:bg-white/[.03] transition"
            >
              <span className="font-mono text-[12px] font-semibold text-neutral-300">{t.ticker}</span>
              <span className="font-mono text-[12px] tabular" style={{ color }}>
                {up ? "▲" : down ? "▼" : "·"} {t.s > 0 ? "+" : ""}
                {t.s.toFixed(2)}
              </span>
            </LocaleLink>
          );
        })}
      </div>
      <div className="pointer-events-none absolute inset-y-0 left-0 w-12 bg-gradient-to-r from-ink to-transparent" />
      <div className="pointer-events-none absolute inset-y-0 right-0 w-12 bg-gradient-to-l from-ink to-transparent" />
    </div>
  );
}
