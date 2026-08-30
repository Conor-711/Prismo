"use client";

import { useState } from "react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { TickerLogo } from "@/shared/market/TickerLogo";
import { RegionBadge, SentScore } from "@/shared/ui/bsmartBits";
import { fmtCompact } from "@/shared/formatting/format";
import type { Locale } from "@/lib/i18n";
import type { DashboardSignalItem, DashboardSignalKey } from "../types";

const TAB_LABELS: Record<DashboardSignalKey, { zh: string; en: string }> = {
  divergence: { zh: "分歧", en: "Divergence" },
  bullish: { zh: "看多", en: "Bullish" },
  bearish: { zh: "看空", en: "Bearish" },
};

export function DashboardSignalPanel({
  signals,
  lang,
}: {
  signals: Record<DashboardSignalKey, DashboardSignalItem[]>;
  lang: Locale;
}) {
  const [active, setActive] = useState<DashboardSignalKey>("divergence");
  const zh = lang === "zh";
  const items = signals[active];

  return (
    <section className="panel flex h-full min-h-0 flex-col overflow-hidden rounded-lg">
      <div className="flex h-11 shrink-0 items-center justify-between gap-3 border-b border-line px-3">
        <div className="min-w-0">
          <h2 className="truncate font-display text-[14px] font-bold text-cream">
            {zh ? "市场信号" : "Market signals"}
          </h2>
        </div>
        <div className="flex shrink-0 items-center rounded-md bg-black/10 p-0.5 ring-1 ring-inset ring-line">
          {(Object.keys(TAB_LABELS) as DashboardSignalKey[]).map((key) => (
            <button
              key={key}
              type="button"
              aria-pressed={active === key}
              onClick={() => setActive(key)}
              className={`rounded px-2 py-1 text-[10.5px] font-semibold transition ${
                active === key
                  ? "bg-reddit/12 text-reddit ring-1 ring-inset ring-reddit/35"
                  : "text-neutral-500 hover:text-cream"
              }`}
            >
              {zh ? TAB_LABELS[key].zh : TAB_LABELS[key].en}
            </button>
          ))}
        </div>
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto">
        {items.map((item, index) => (
          <LocaleLink
            key={item.ticker}
            href={`/tickers/${item.ticker}`}
            className="grid min-h-[44px] grid-cols-[24px_minmax(0,1fr)_auto] items-center gap-2.5 border-b border-line/70 px-3 py-1.5 transition last:border-b-0 hover:bg-white/[.035]"
          >
            <TickerLogo ticker={item.ticker} size={22} />
            <div className="min-w-0">
              <div className="flex min-w-0 items-center gap-2">
                <span className="font-mono text-[12px] font-bold text-cream">{item.ticker}</span>
                <span className="truncate text-[10.5px] text-neutral-500">
                  {zh ? item.nameZh || item.nameEn : item.nameEn || item.nameZh}
                </span>
              </div>
              <div className="mt-0.5 flex items-center gap-2 text-[9.5px] text-neutral-600">
                <span>#{index + 1}</span>
                <span>{fmtCompact(item.posts)} {zh ? "讨论" : "posts"}</span>
                {active === "divergence" && item.divergentRegion && (
                  <RegionBadge region={item.divergentRegion} lang={lang} className="!text-[9.5px] !text-neutral-500" />
                )}
              </div>
            </div>
            <div className="text-right">
              {active === "divergence" && (
                <div className="font-mono text-[11px] font-semibold tabular text-reddit">Δ{item.spread.toFixed(2)}</div>
              )}
              <SentScore score={item.sentiment} className="text-[10.5px]" />
            </div>
          </LocaleLink>
        ))}
      </div>
    </section>
  );
}
