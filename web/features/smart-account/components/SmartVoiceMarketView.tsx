"use client";

import { useMemo, useState } from "react";
import { TickerLogo } from "@/shared/market/TickerLogo";
import type { SmartVoiceMarketData, SmartVoiceMarketSource, SmartVoiceMarketWindow } from "@/server/queries/smartVoiceQueries";
import {
  highRatio,
  MARKET_SOURCES,
  MARKET_WINDOWS,
  metricColor,
  metricText,
  MODE_META,
  platformKeyOf,
  signalLabel,
  signed,
  signedInteger,
  type MarketMode,
} from "../smartVoiceMarketModel";
import { SmartVoiceMarketDetail } from "./SmartVoiceMarketDetail";

export function SmartVoiceMarketView({
  marketData,
  zh,
}: {
  marketData: SmartVoiceMarketData;
  zh: boolean;
}) {
  const [windowKey, setWindowKey] = useState<SmartVoiceMarketWindow>("7D");
  const [sources, setSources] = useState<SmartVoiceMarketSource[]>(["x", "youtube", "reddit", "xueqiu"]);
  const [mode, setMode] = useState<MarketMode>("newCoverage");
  const [query, setQuery] = useState("");
  const [selectedTicker, setSelectedTicker] = useState("");
  const platformKey = platformKeyOf(sources);
  const rows = useMemo(() => {
    const q = query.trim().toUpperCase();
    return marketData.boards[platformKey][windowKey][mode].filter((row) =>
      !q || row.ticker.includes(q) || row.nameZh.includes(query) || row.nameEn.toUpperCase().includes(q)
    );
  }, [marketData.boards, mode, platformKey, query, windowKey]);
  const selected = rows.find((row) => row.ticker === selectedTicker) ?? rows[0];
  const color = selected ? metricColor(selected, mode) : MODE_META[mode].color;

  return (
    <div className="grid h-full min-h-0 lg:grid-cols-[minmax(0,1fr)_360px] xl:grid-cols-[minmax(0,1fr)_420px] 2xl:grid-cols-[minmax(0,1fr)_460px]">
      <section className="flex min-h-0 min-w-0 flex-col">
        <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-line px-3 py-2.5">
          <div className="inline-flex h-8 items-center rounded-lg bg-white/[.025] p-0.5 ring-1 ring-inset ring-line">
            {(Object.keys(MODE_META) as MarketMode[]).map((key) => (
              <button
                key={key}
                type="button"
                onClick={() => {
                  setMode(key);
                  setSelectedTicker("");
                }}
                className={`h-7 rounded-md px-3 text-[11.5px] font-semibold outline-none transition focus-visible:ring-1 focus-visible:ring-inset focus-visible:ring-reddit/50 ${mode === key ? "bg-elevated text-cream ring-1 ring-inset ring-white/10" : "text-neutral-500 hover:text-cream"}`}
              >
                <span className="mr-1.5 inline-block h-1.5 w-1.5 rounded-full" style={{ background: MODE_META[key].color }} />
                {zh ? MODE_META[key].zh : MODE_META[key].en}
              </button>
            ))}
          </div>
          <div className="inline-flex h-8 items-center gap-0.5 rounded-lg p-0.5 ring-1 ring-inset ring-line" role="group" aria-label={zh ? "筛选来源平台" : "Filter source platforms"}>
            {MARKET_SOURCES.map((source) => {
              const active = sources.includes(source.key);
              const lastActive = active && sources.length === 1;
              return (
                <label
                  key={source.key}
                  className={`flex h-7 cursor-pointer items-center gap-1.5 rounded-md px-2 text-[10.5px] font-semibold transition ${active ? "bg-white/[.055] text-cream" : "text-neutral-600 hover:text-neutral-400"} ${lastActive ? "cursor-default" : ""}`}
                >
                  <input
                    type="checkbox"
                    checked={active}
                    disabled={lastActive}
                    onChange={() => {
                      setSources((current) => active
                        ? current.filter((key) => key !== source.key)
                        : MARKET_SOURCES.map((item) => item.key).filter((key) => [...current, source.key].includes(key)));
                      setSelectedTicker("");
                    }}
                    className="sr-only"
                  />
                  <span
                    aria-hidden
                    className="grid h-3.5 w-3.5 place-items-center rounded-[3px] text-[9px] font-bold ring-1 ring-inset"
                    style={{ color: active ? source.color : "#69727D", boxShadow: `inset 0 0 0 1px ${active ? source.color : "#3A414A"}` }}
                  >
                    {active ? "✓" : ""}
                  </span>
                  {source.label}
                </label>
              );
            })}
          </div>
          <div className="inline-flex h-8 items-center rounded-lg p-0.5 ring-1 ring-inset ring-line">
            {MARKET_WINDOWS.map((key) => (
              <button
                key={key}
                type="button"
                onClick={() => {
                  setWindowKey(key);
                  setSelectedTicker("");
                }}
                className={`h-7 rounded-md px-2.5 font-mono text-[11px] font-semibold outline-none transition focus-visible:ring-1 focus-visible:ring-inset focus-visible:ring-reddit/50 ${windowKey === key ? "bg-reddit/12 text-reddit ring-1 ring-inset ring-reddit/30" : "text-neutral-500 hover:text-cream"}`}
              >
                {key}
              </button>
            ))}
          </div>
          <label className="ml-auto flex h-8 min-w-[190px] max-w-[280px] flex-1 items-center gap-2 rounded-lg px-2.5 ring-1 ring-inset ring-line focus-within:ring-reddit/50">
            <span aria-hidden className="text-[13px] text-neutral-600">⌕</span>
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder={zh ? "搜索标的" : "Search ticker"}
              className="min-w-0 flex-1 bg-transparent text-[12px] text-cream outline-none placeholder:text-neutral-700"
            />
          </label>
        </div>

        <div className="grid shrink-0 grid-cols-[42px_minmax(150px,1.15fr)_minmax(150px,1fr)_90px_88px] items-center gap-3 border-b border-line bg-white/[.015] px-3 py-2 text-[10px] font-semibold uppercase tracking-[0.08em] text-neutral-600">
          <span>#</span>
          <span>{zh ? "标的" : "Ticker"}</span>
          <span>{mode === "newCoverage"
            ? (zh ? "新覆盖类型 / 方向" : "Coverage type / direction")
            : mode === "contrast"
              ? (zh ? "高 / 低 Score 净方向" : "High / low-Score net")
              : mode === "authorShift" ? (zh ? "前期 → 本期净人数" : "Previous → current net") : (zh ? "Top 10% 作者方向" : "Top 10% direction")}</span>
          <span className="text-right" title={zh ? "每位 Top 10% 作者仅保留窗口内最新观点" : "Each Top 10% author contributes their latest call only"}>{mode === "newCoverage"
            ? (zh ? "新增 / 当前" : "New / current")
            : mode === "contrast"
              ? (zh ? "高/低作者" : "High/low voices")
              : mode === "authorShift" ? (zh ? "净变化" : "Net change") : (zh ? "作者净人数" : "Net authors")}</span>
          <span className="text-right">{mode === "newCoverage" ? (zh ? "新增作者" : "New voices") : mode === "contrast" ? "Delta" : mode === "authorShift" ? (zh ? "突变幅度" : "Shift") : (zh ? "净强度" : "Net strength")}</span>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto">
          {rows.map((row, index) => {
            const bullRatio = highRatio(row);
            const active = selected?.ticker === row.ticker;
            return (
              <button
                key={row.ticker}
                type="button"
                onClick={() => setSelectedTicker(row.ticker)}
                className={`grid w-full grid-cols-[42px_minmax(150px,1.15fr)_minmax(150px,1fr)_90px_88px] items-center gap-3 border-b border-line/70 px-3 py-2.5 text-left transition ${active ? "bg-reddit/[.055] shadow-[inset_2px_0_0_#57D7BA]" : "hover:bg-white/[.025]"}`}
              >
                <span className="font-mono text-[11px] text-neutral-600">{String(index + 1).padStart(2, "0")}</span>
                <span className="flex min-w-0 items-center gap-2.5">
                  <TickerLogo ticker={row.ticker} size={28} />
                  <span className="min-w-0">
                    <span className="block font-mono text-[13px] font-bold text-cream">{row.ticker}</span>
                    <span className="block truncate text-[10.5px] text-neutral-600">{zh ? row.nameZh : row.nameEn}</span>
                  </span>
                </span>
                <span className="min-w-0">
                  {mode === "newCoverage" ? (
                    <span className="flex items-center justify-between gap-2 text-[10.5px]">
                      <span className={`shrink-0 rounded-[3px] px-1.5 py-0.5 text-[9px] font-semibold ring-1 ring-inset ${row.cohortNew ? "bg-[#6EA8FE]/12 text-[#8CBBFF] ring-[#6EA8FE]/25" : "text-neutral-500 ring-line"}`}>
                        {row.cohortNew ? (zh ? "全新进入" : "New to cohort") : (zh ? "新作者加入" : "New voices")}
                      </span>
                      <span className="truncate text-neutral-600">
                        <span className="text-bull">{row.newCoverageBullCount}</span>
                        <span className="px-1">/</span>
                        <span className="text-bear">{row.newCoverageBearCount}</span>
                      </span>
                    </span>
                  ) : mode === "contrast" ? (
                    <span className="flex items-center justify-between gap-2 text-[10.5px]">
                      <span className={row.highNet >= 0 ? "text-bull" : "text-bear"}>Top {signed(row.highNet)}</span>
                      <span className="truncate text-neutral-600">{signalLabel(row.signal, zh)}</span>
                      <span className={row.lowNet >= 0 ? "text-bull" : "text-bear"}>Bottom {signed(row.lowNet)}</span>
                    </span>
                  ) : mode === "authorShift" ? (
                    <span className="flex items-center justify-between gap-2 font-mono text-[11px]">
                      <span className={row.previousHighAuthorNet >= 0 ? "text-bull" : "text-bear"}>{signedInteger(row.previousHighAuthorNet)}</span>
                      <span className={`rounded-[3px] px-1.5 py-0.5 font-sans text-[9px] font-semibold ${row.authorNetAbrupt ? "bg-[#6EA8FE]/12 text-[#8CBBFF] ring-1 ring-inset ring-[#6EA8FE]/25" : "text-neutral-600 ring-1 ring-inset ring-line"}`}>
                        {row.authorNetAbrupt ? (zh ? "突变" : "Abrupt") : (zh ? "变化" : "Change")}
                      </span>
                      <span className={row.highAuthorNet >= 0 ? "text-bull" : "text-bear"}>{signedInteger(row.highAuthorNet)}</span>
                    </span>
                  ) : (
                    <>
                      <span className="mb-1 flex items-center justify-between text-[10.5px]">
                        <span className="text-bull">{row.highBullCalls}</span>
                        <span className="truncate px-2 text-neutral-600">{signalLabel(row.signal, zh)}</span>
                        <span className="text-bear">{row.highBearCalls}</span>
                      </span>
                      <span className="flex h-1.5 overflow-hidden rounded-full bg-bear/70">
                        <span className="h-full bg-bull" style={{ width: `${bullRatio}%` }} />
                      </span>
                    </>
                  )}
                </span>
                {mode === "newCoverage" ? (
                  <span className="text-right font-mono text-[11px] text-neutral-300">
                    {row.newCoverageAuthorCount}/{row.currentTopAuthorCount}
                  </span>
                ) : mode === "contrast" ? (
                  <span className="text-right font-mono text-[12px] text-neutral-300">{row.highVoices}/{row.lowVoices}</span>
                ) : mode === "authorShift" ? (
                  <span className={`text-right font-mono text-[12px] font-bold ${row.authorNetDelta >= 0 ? "text-bull" : "text-bear"}`}>{signedInteger(row.authorNetDelta)}</span>
                ) : (
                  <span className="text-right font-mono">
                    <span className={`block text-[12px] font-bold ${row.highAuthorNet >= 0 ? "text-bull" : "text-bear"}`}>{signedInteger(row.highAuthorNet)}</span>
                    <span className="block text-[8.5px] text-neutral-600">{row.highAuthorBullCount}/{row.highAuthorBearCount}</span>
                  </span>
                )}
                <span className="text-right font-mono text-[14px] font-bold" style={{ color: metricColor(row, mode) }}>
                  {metricText(row, mode)}
                </span>
              </button>
            );
          })}
          {!rows.length ? <div className="grid h-full place-items-center text-[12px] text-neutral-600">{zh ? "没有匹配的标的" : "No matching tickers"}</div> : null}
        </div>
      </section>

      <SmartVoiceMarketDetail
        selected={selected}
        mode={mode}
        windowKey={windowKey}
        sources={sources}
        latestAt={marketData.latestAt}
        evidenceById={marketData.evidenceById}
        color={color}
        zh={zh}
      />
    </div>
  );
}
