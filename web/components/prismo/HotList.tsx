"use client";

import { useState } from "react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { SentScore, StanceBar } from "./Bits";
import { TickerLogo } from "./TickerLogo";
import { Delta } from "./DetailBits";
import { fmtCompact } from "@/lib/format";
import type { Locale } from "@/lib/i18n";

type Row = {
  ticker: string; rank: number; posts: number; vsBaseline: number;
  sentiment: number; sentimentChange: number; bullPct: number; bearPct: number; isNew: boolean;
};

// 模块 2「热榜 & 发现」：绝对热榜 / 飙升榜 / 新晋 三类榜单切换。
export function HotList({ abs, surge, fresh, lang }: { abs: Row[]; surge: Row[]; fresh: Row[]; lang: Locale }) {
  const zh = lang === "zh";
  const [tab, setTab] = useState<"abs" | "surge" | "fresh">("abs");
  const rows = tab === "abs" ? abs : tab === "surge" ? surge : fresh;
  const tabs: { k: typeof tab; label: string }[] = [
    { k: "abs", label: zh ? "绝对热榜" : "Top" },
    { k: "surge", label: zh ? "飙升榜" : "Surging" },
    { k: "fresh", label: zh ? "新晋" : "New" },
  ];

  return (
    <div>
      <div className="flex gap-1 px-4 py-2.5 border-b border-line">
        {tabs.map((t) => (
          <button
            key={t.k}
            onClick={() => setTab(t.k)}
            className={`px-2.5 py-1 rounded-md text-[12px] font-medium transition ${tab === t.k ? "bg-white/[.06] text-cream" : "text-neutral-500 hover:text-neutral-300"}`}
          >
            {t.label}
          </button>
        ))}
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-[11px] uppercase tracking-wider text-neutral-500 bg-white/[.02]">
              <th className="text-right font-medium pl-4 pr-1 py-2 w-8">#</th>
              <th className="text-left font-medium px-3 py-2">{zh ? "标的" : "Ticker"}</th>
              <th className="text-right font-medium px-3 py-2">{zh ? "讨论量" : "Posts"}</th>
              <th className="text-right font-medium px-3 py-2">{tab === "surge" ? (zh ? "vs常态" : "vs base") : zh ? "情绪Δ" : "Sent Δ"}</th>
              <th className="text-left font-medium px-3 py-2 hidden sm:table-cell w-28">{zh ? "多空" : "Stance"}</th>
              <th className="text-right font-medium pl-3 pr-4 py-2">{zh ? "情绪" : "Sent"}</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.ticker} className="border-t border-line hover:bg-white/[.03] transition">
                <td className="pl-4 pr-1 py-2.5 text-right text-xs text-neutral-600 tabular">{r.rank}</td>
                <td className="px-3 py-2.5">
                  <LocaleLink href={`/tickers/${r.ticker}`} className="inline-flex items-center gap-2.5 hover:text-reddit transition">
                    <TickerLogo ticker={r.ticker} size={22} />
                    <span className="font-mono font-bold text-cream">{r.ticker}</span>
                    {r.isNew && <span className="text-[9px] px-1 py-0.5 rounded bg-reddit/15 text-reddit ring-1 ring-inset ring-reddit/30">{zh ? "新" : "NEW"}</span>}
                  </LocaleLink>
                </td>
                <td className="px-3 py-2.5 text-right text-neutral-300 tabular">{fmtCompact(r.posts)}</td>
                <td className="px-3 py-2.5 text-right font-mono text-[12px] tabular">
                  {tab === "surge" ? <span className="text-reddit">×{r.vsBaseline}</span> : <Delta value={r.sentimentChange} />}
                </td>
                <td className="px-3 py-2.5 hidden sm:table-cell">
                  <div className="w-24"><StanceBar bull={r.bullPct} bear={r.bearPct} neutral={Math.max(0, 100 - r.bullPct - r.bearPct)} /></div>
                </td>
                <td className="pl-3 pr-4 py-2.5 text-right"><SentScore score={r.sentiment} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
