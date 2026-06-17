"use client";

import { TickerChip, ScoreNum } from "./ui";
import { useLocale } from "./i18n/LocaleProvider";
import type { NarrativeRow } from "@/lib/queries";

// 叙事卡：把一条叙事拆成若干「字段」呈现——讨论帖子数 / 情绪 / 热度 / 提到的 Ticker。
export function NarrativeCard({ n, maxHeat = 1, tickerBase = "/ticker" }: { n: NarrativeRow; maxHeat?: number; tickerBase?: string }) {
  const { dict } = useLocale();
  const c = dict.common;
  const nd = dict.narratives;
  // 热度条按当前展示集合内的最大热度归一（maxHeat 由页面传入），
  // 避免固定除数(旧的 /16000)在「新帖普遍低分」的窗口里把所有卡都压到同一个下限值。
  const heatPct = Math.min(100, Math.max(3, Math.round((n.heat / Math.max(1, maxHeat)) * 100)));

  return (
    <div className="panel rounded-xl p-4 panel-hover h-full flex flex-col">
      <h3 className="font-display font-bold text-cream text-[15px] leading-tight">{n.name}</h3>

      {/* 字段区：讨论帖子数 / 情绪 / 热度 */}
      <div className="mt-3 space-y-2 text-[12.5px]">
        <Field label={nd.fPosts}>
          <span className="font-mono tabular font-semibold text-cream">{n.post_count}</span>
          <span className="text-neutral-500"> {c.postsSuffix}</span>
        </Field>
        <Field label={nd.fSentiment}>
          <ScoreNum score={n.sentiment} />
        </Field>
        <Field label={nd.fHeat}>
          <div className="flex items-center gap-2 w-24 ml-auto">
            <div className="h-1.5 flex-1 rounded-full bg-white/[.06] overflow-hidden">
              <div className="h-full rounded-full bg-gradient-to-r from-reddit/60 to-reddit" style={{ width: `${heatPct}%` }} />
            </div>
            <span className="font-mono tabular text-[11px] text-neutral-500 shrink-0">{heatPct}</span>
          </div>
        </Field>
      </div>

      {/* 提到的 Ticker */}
      <div className="mt-3 pt-3 border-t border-line">
        <div className="text-[10px] uppercase tracking-wider text-neutral-600 mb-1.5">{nd.fTickers}</div>
        <div className="flex flex-wrap gap-1.5">
          {n.tickers.slice(0, 6).map((t) => (
            <TickerChip key={t.ticker} ticker={t.ticker} size="xs" base={tickerBase} />
          ))}
          {n.tickers.length === 0 && <span className="text-xs text-neutral-600">—</span>}
        </div>
      </div>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <span className="text-neutral-500 shrink-0">{label}</span>
      <span className="min-w-0 text-right">{children}</span>
    </div>
  );
}
