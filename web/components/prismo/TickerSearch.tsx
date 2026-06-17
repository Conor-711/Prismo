"use client";

import { useState, useMemo } from "react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { SentScore, Consensus } from "./Bits";
import { fmtCompact } from "@/lib/format";
import type { Locale } from "@/lib/i18n";
import type { GrTickerRow } from "@/lib/globalQueries";

export function TickerSearch({ rows, lang }: { rows: GrTickerRow[]; lang: Locale }) {
  const zh = lang === "zh";
  const [q, setQ] = useState("");
  const name = (t: GrTickerRow) => (zh ? t.name_zh || t.name_en : t.name_en || t.name_zh);
  const f = q.trim().toUpperCase();

  const results = useMemo(() => {
    if (!f) return [];
    return rows
      .filter((t) => t.ticker.includes(f) || (t.name_en || "").toUpperCase().includes(f) || (t.name_zh || "").includes(q.trim()))
      .sort((a, b) => b.total_posts - a.total_posts)
      .slice(0, 40);
  }, [rows, f, q]);

  const popular = useMemo(() => [...rows].sort((a, b) => b.total_posts - a.total_posts).slice(0, 12), [rows]);

  return (
    <div className="max-w-2xl mx-auto">
      <div className="relative">
        <svg className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-neutral-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
          <circle cx="11" cy="11" r="7" /><path d="m21 21-4.3-4.3" />
        </svg>
        {/* eslint-disable-next-line jsx-a11y/no-autofocus */}
        <input
          autoFocus
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder={zh ? "搜索标的代码或公司名，如 NVDA、英伟达…" : "Search a ticker or company, e.g. NVDA…"}
          className="w-full rounded-xl bg-card ring-1 ring-inset ring-line pl-12 pr-4 py-3.5 text-[15px] text-cream placeholder:text-neutral-600 focus:outline-none focus:ring-2 focus:ring-reddit/60"
        />
      </div>

      {f ? (
        <div className="mt-4 rounded-xl ring-1 ring-inset ring-line overflow-hidden">
          {results.length ? (
            results.map((t) => (
              <LocaleLink key={t.ticker} href={`/tickers/${t.ticker}`} className="flex items-center gap-3 px-4 py-3 border-b border-line last:border-0 hover:bg-white/[.04] transition">
                <span className="font-mono font-bold text-cream text-[15px] w-20 shrink-0">{t.ticker}</span>
                <span className="text-sm text-neutral-400 truncate flex-1">{name(t)}</span>
                <Consensus value={t.consensus} lang={lang} />
                <span className="text-[11px] text-neutral-600 tabular hidden sm:inline">{fmtCompact(t.total_posts)} {zh ? "帖" : "posts"}</span>
                <SentScore score={t.avg_sentiment} className="w-14 text-right" />
              </LocaleLink>
            ))
          ) : (
            <div className="px-4 py-10 text-center text-sm text-neutral-600">
              {zh ? `没有匹配「${q.trim()}」的标的。` : `No tickers match “${q.trim()}”.`}
            </div>
          )}
        </div>
      ) : (
        <div className="mt-6">
          <div className="text-[11px] uppercase tracking-wider text-neutral-500 mb-2.5">{zh ? "热门标的" : "Popular"}</div>
          <div className="flex flex-wrap gap-2">
            {popular.map((t) => (
              <LocaleLink
                key={t.ticker}
                href={`/tickers/${t.ticker}`}
                className="inline-flex items-center gap-2 rounded-full bg-card ring-1 ring-inset ring-line px-3 py-1.5 hover:ring-reddit/40 transition"
              >
                <span className="font-mono font-bold text-cream text-[13px]">{t.ticker}</span>
                <SentScore score={t.avg_sentiment} className="text-[11px]" />
              </LocaleLink>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
