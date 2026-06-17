"use client";

import { useState, useMemo } from "react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { SentScore, Consensus } from "./Bits";
import { TickerLogo } from "./TickerLogo";
import { fmtCompact } from "@/lib/format";
import type { Locale } from "@/lib/i18n";
import type { GrTickerRow } from "@/lib/globalQueries";

type SortKey = "ticker" | "regions_present" | "total_posts" | "avg_sentiment" | "spread";

export function TickerTable({ rows, lang }: { rows: GrTickerRow[]; lang: Locale }) {
  const zh = lang === "zh";
  const [sort, setSort] = useState<SortKey>("total_posts");
  const [dir, setDir] = useState<1 | -1>(-1);
  const [q, setQ] = useState("");

  const sorted = useMemo(() => {
    const f = q.trim().toUpperCase();
    let r = rows;
    if (f)
      r = rows.filter(
        (x) => x.ticker.includes(f) || (x.name_en || "").toUpperCase().includes(f) || (x.name_zh || "").includes(q.trim())
      );
    return [...r].sort((a, b) => {
      const av = a[sort] as string | number, bv = b[sort] as string | number;
      if (typeof av === "string" && typeof bv === "string") return dir * av.localeCompare(bv);
      return dir * ((Number(av) || 0) - (Number(bv) || 0));
    });
  }, [rows, sort, dir, q]);

  const name = (t: GrTickerRow) => (zh ? t.name_zh || t.name_en : t.name_en || t.name_zh);
  const th = (key: SortKey, label: string, align = "") => (
    <button
      onClick={() => (sort === key ? setDir((d) => (d === 1 ? -1 : 1)) : (setSort(key), setDir(-1)))}
      className={`inline-flex items-center gap-1 hover:text-cream transition ${align} ${sort === key ? "text-cream" : ""}`}
    >
      {label}
      {sort === key && <span className="text-[9px]">{dir === 1 ? "▲" : "▼"}</span>}
    </button>
  );

  return (
    <div>
      <input
        value={q}
        onChange={(e) => setQ(e.target.value)}
        placeholder={zh ? "筛选标的 / 名称…" : "Filter ticker / name…"}
        className="mb-3 w-full sm:w-72 rounded-lg bg-card ring-1 ring-inset ring-line px-3 py-2 text-sm text-cream placeholder:text-neutral-600 focus:outline-none focus:ring-2 focus:ring-reddit/50"
      />
      <div className="overflow-x-auto rounded-xl ring-1 ring-inset ring-line">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-[11px] uppercase tracking-wider text-neutral-500 bg-white/[.02]">
              <th className="text-left font-medium px-3 py-2.5">{th("ticker", zh ? "标的" : "Ticker")}</th>
              <th className="text-left font-medium px-3 py-2.5 hidden sm:table-cell">{zh ? "名称" : "Name"}</th>
              <th className="text-center font-medium px-3 py-2.5">{th("regions_present", zh ? "覆盖区" : "Regions")}</th>
              <th className="text-right font-medium px-3 py-2.5">{th("total_posts", zh ? "帖数" : "Posts")}</th>
              <th className="text-right font-medium px-3 py-2.5">{th("avg_sentiment", zh ? "情绪" : "Sentiment")}</th>
              <th className="text-left font-medium px-3 py-2.5 hidden md:table-cell">{zh ? "共识" : "Consensus"}</th>
              <th className="text-right font-medium px-3 py-2.5">{th("spread", zh ? "分歧" : "Spread")}</th>
            </tr>
          </thead>
          <tbody>
            {sorted.map((t) => (
              <tr key={t.ticker} className="border-t border-line hover:bg-white/[.03] transition">
                <td className="px-3 py-2.5">
                  <LocaleLink href={`/tickers/${t.ticker}`} className="inline-flex items-center gap-2.5 hover:text-reddit transition">
                    <TickerLogo ticker={t.ticker} size={24} />
                    <span className="font-mono font-bold text-cream">{t.ticker}</span>
                  </LocaleLink>
                </td>
                <td className="px-3 py-2.5 text-neutral-400 truncate max-w-[220px] hidden sm:table-cell">{name(t)}</td>
                <td className="px-3 py-2.5 text-center text-neutral-400 tabular">{t.regions_present}</td>
                <td className="px-3 py-2.5 text-right text-neutral-300 tabular">{fmtCompact(t.total_posts)}</td>
                <td className="px-3 py-2.5 text-right"><SentScore score={t.avg_sentiment} /></td>
                <td className="px-3 py-2.5 hidden md:table-cell"><Consensus value={t.consensus} lang={lang} /></td>
                <td className="px-3 py-2.5 text-right font-mono text-[12px] tabular text-neutral-400">{(t.spread ?? 0).toFixed(2)}</td>
              </tr>
            ))}
            {sorted.length === 0 && (
              <tr>
                <td colSpan={7} className="px-3 py-8 text-center text-sm text-neutral-600">{zh ? "无匹配标的。" : "No matches."}</td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
