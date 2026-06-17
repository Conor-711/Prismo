"use client";

import { useEffect, useState } from "react";
import { LocaleLink } from "./i18n/LocaleLink";
import { useLocale } from "./i18n/LocaleProvider";
import { IconFlame, IconArrow } from "./icons";
import { fetchTopSearches } from "@/lib/searchCounts";

export interface HeatItem { ticker: string; name: string; mentions: number; sentiment: number; base?: string }
type Row = { ticker: string; name: string; value: number; sentiment?: number; base?: string };

// 搜索热度榜：优先全网真实搜索次数（Supabase），未配置/为空时降级到真实社区讨论热度。
// bases：全站搜索下每个标的的个股页前缀（/ticker 或 /cn/ticker），保证点进去落到正确市场页。
export function SearchLeaderboard({
  heat,
  names,
  tickerBase = "/ticker",
  bases,
}: {
  heat: HeatItem[];
  names: Record<string, string>;
  tickerBase?: string;
  bases?: Record<string, string>;
}) {
  const { dict } = useLocale();
  const t = dict.search;
  const heatRows: Row[] = heat.map((h) => ({ ticker: h.ticker, name: h.name, value: h.mentions, sentiment: h.sentiment, base: h.base }));
  const [rows, setRows] = useState<Row[]>(heatRows);
  const [live, setLive] = useState(false);

  useEffect(() => {
    let alive = true;
    fetchTopSearches(10).then((top) => {
      if (!alive || top.length === 0) return; // 空 → 保持社区热度兜底
      setRows(top.map((r) => ({ ticker: r.ticker, name: names[r.ticker] ?? "", value: r.count, base: bases?.[r.ticker] })));
      setLive(true);
    });
    return () => {
      alive = false;
    };
  }, [names, bases]);

  if (rows.length === 0) {
    return <p className="text-sm text-neutral-500 text-center py-8">{t.empty}</p>;
  }

  const unit = live ? t.searchesUnit : t.mentionsUnit;

  return (
    <section>
      <div className="flex items-end justify-between gap-3 mb-3">
        <div className="flex items-center gap-2.5">
          <span className="grid place-items-center w-7 h-7 rounded-lg bg-reddit/15 text-reddit shrink-0">
            <IconFlame className="w-4 h-4" />
          </span>
          <div>
            <h2 className="font-display font-bold text-cream text-[15px] leading-tight">
              {live ? t.rankTitleLive : t.rankTitleHeat}
            </h2>
            <p className="text-[11px] text-neutral-500 leading-tight mt-0.5">
              {live ? t.rankSubLive : t.rankSubHeat}
            </p>
          </div>
        </div>
      </div>

      <ol className="rounded-2xl ring-1 ring-inset ring-line overflow-hidden bg-white/[.02]">
        {rows.map((r, i) => (
          <li key={r.ticker}>
            <LocaleLink
              href={`${r.base ?? bases?.[r.ticker] ?? tickerBase}/${r.ticker}`}
              className="group flex items-center gap-3 px-3.5 py-2.5 border-b border-line last:border-0 hover:bg-reddit/[.06] transition"
            >
              <span className={rankClass(i)}>{i + 1}</span>
              <span className="font-mono font-bold text-cream text-sm w-16 shrink-0 group-hover:text-reddit transition">
                {r.ticker}
              </span>
              <span className="text-xs text-neutral-500 truncate flex-1 min-w-0">{r.name}</span>
              <span className="font-mono tabular text-sm text-neutral-300 shrink-0">
                {fmt(r.value)}
                <span className="text-[11px] text-neutral-600 ml-1">{unit}</span>
              </span>
              <IconArrow className="w-3.5 h-3.5 text-neutral-700 group-hover:text-reddit group-hover:translate-x-0.5 transition shrink-0" />
            </LocaleLink>
          </li>
        ))}
      </ol>
    </section>
  );
}

function rankClass(i: number) {
  const base = "grid place-items-center w-6 h-6 rounded-md text-[12px] font-bold shrink-0 tabular ";
  if (i === 0) return base + "bg-gold/20 text-gold ring-1 ring-inset ring-gold/30";
  if (i === 1) return base + "bg-white/10 text-neutral-200 ring-1 ring-inset ring-white/15";
  if (i === 2) return base + "bg-reddit/12 text-reddit/90 ring-1 ring-inset ring-reddit/25";
  return base + "text-neutral-600";
}

function fmt(n: number) {
  return n >= 1000 ? `${(n / 1000).toFixed(1)}k` : `${n}`;
}
