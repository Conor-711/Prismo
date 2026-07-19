"use client";

import { useMemo, useState } from "react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { TickerLogo } from "@/shared/market/TickerLogo";
import type { SmartVoiceMarketData, SmartVoiceMarketPlatformKey, SmartVoiceMarketSource, SmartVoiceMarketWindow, SmartVoiceTickerEvidence, SmartVoiceTickerRank } from "@/server/queries/smartVoiceQueries";

const MARKET_WINDOWS: SmartVoiceMarketWindow[] = ["24H", "3D", "7D", "30D", "90D"];
const MARKET_SOURCES: { key: SmartVoiceMarketSource; label: string; color: string }[] = [
  { key: "x", label: "X", color: "#D7DCE2" },
  { key: "youtube", label: "YouTube", color: "#FF5C6C" },
  { key: "reddit", label: "Reddit", color: "#FF8A5B" },
  { key: "xueqiu", label: "雪球", color: "#5BA3C4" },
];

const MODE_META = {
  bullish: { zh: "集中看多", en: "Bullish focus", color: "#57D7BA" },
  bearish: { zh: "集中看空", en: "Bearish focus", color: "#FF5C6C" },
  contrast: { zh: "高低 SV 分歧", en: "SV divergence", color: "#F7D14E" },
  authorShift: { zh: "作者净人数突变", en: "Author shifts", color: "#6EA8FE" },
} as const;

type MarketMode = keyof typeof MODE_META;

function signalLabel(signal: SmartVoiceTickerRank["signal"], zh: boolean) {
  const labels: Record<SmartVoiceTickerRank["signal"], [string, string]> = {
    high_bull_low_bear: ["高 SV 看多，低 SV 看空", "High-SV bull, low-SV bear"],
    high_bear_low_bull: ["高 SV 看空，低 SV 看多", "High-SV bear, low-SV bull"],
    sv_consensus_bull: ["高 SV 看多共识", "High-SV bullish consensus"],
    sv_consensus_bear: ["高 SV 看空共识", "High-SV bearish consensus"],
    mixed: ["观点仍有分歧", "Views remain mixed"],
  };
  return labels[signal][zh ? 0 : 1];
}

function metricFor(row: SmartVoiceTickerRank, mode: MarketMode) {
  if (mode === "bullish" || mode === "bearish") return row.highNet;
  if (mode === "authorShift") return row.authorNetShiftPct;
  return row.contrastScore;
}

function highRatio(row: SmartVoiceTickerRank) {
  return row.highBullCalls + row.highBearCalls ? (row.highBullCalls / (row.highBullCalls + row.highBearCalls)) * 100 : 50;
}

function metricText(row: SmartVoiceTickerRank, mode: MarketMode) {
  const value = metricFor(row, mode);
  if (mode === "contrast") return `Δ${value.toFixed(1)}`;
  if (mode === "authorShift") return `${value > 0 ? "+" : ""}${value.toFixed(1)}%`;
  return `${value > 0 ? "+" : ""}${value.toFixed(1)}`;
}

function metricColor(row: SmartVoiceTickerRank, mode: MarketMode) {
  if (mode === "authorShift") return row.authorNetShiftPct >= 0 ? "#57D7BA" : "#FF5C6C";
  return MODE_META[mode].color;
}

function signed(value: number) {
  return `${value > 0 ? "+" : ""}${value.toFixed(1)}`;
}

function signedInteger(value: number) {
  return `${value > 0 ? "+" : ""}${value}`;
}

function evidenceGroups(row: SmartVoiceTickerRank, mode: MarketMode) {
  if (mode === "bullish") return { primary: row.evidenceIds.highBull, counter: row.evidenceIds.highBear };
  if (mode === "bearish") return { primary: row.evidenceIds.highBear, counter: row.evidenceIds.highBull };
  if (mode === "authorShift") {
    const current = row.highAuthorNet > 0
      ? row.evidenceIds.highBull
      : row.highAuthorNet < 0 ? row.evidenceIds.highBear : [...row.evidenceIds.highBull, ...row.evidenceIds.highBear];
    const previous = row.previousHighAuthorNet > 0
      ? row.evidenceIds.previousHighBull
      : row.previousHighAuthorNet < 0 ? row.evidenceIds.previousHighBear : [...row.evidenceIds.previousHighBull, ...row.evidenceIds.previousHighBear];
    return { primary: current, counter: previous };
  }
  if (row.highNet >= 0) return { primary: row.evidenceIds.highBull, counter: row.evidenceIds.lowBear };
  return { primary: row.evidenceIds.highBear, counter: row.evidenceIds.lowBull };
}

function evidenceLinkLabel(source: string, zh: boolean) {
  if (!zh) return source === "youtube" ? "Open video" : "Open original";
  return source === "youtube" ? "打开视频" : "打开原帖";
}

function EvidenceItem({ evidence, zh }: { evidence: SmartVoiceTickerEvidence; zh: boolean }) {
  const summary = (zh ? evidence.summaryZh : evidence.summaryEn) || evidence.originalEvidence;
  const showOriginal = evidence.originalEvidence && evidence.originalEvidence.trim() !== summary.trim();
  return (
    <article className="border-t border-line/70 py-2.5 first:border-t-0">
      <div className="flex min-w-0 items-center gap-1.5 text-[9.5px]">
        <span className="font-semibold uppercase text-neutral-400">{evidence.source}</span>
        <span className="truncate text-neutral-500">@{evidence.author.replace(/^@/, "")}</span>
        <span className="ml-auto shrink-0 font-mono text-neutral-600">SV {evidence.platformSv.toFixed(1)}</span>
      </div>
      <p className="mt-1.5 line-clamp-3 text-[10.5px] leading-[1.45] text-neutral-300">{summary}</p>
      {showOriginal ? (
        <p className="mt-1.5 line-clamp-2 border-l-2 border-white/10 pl-2 text-[9.5px] leading-[1.45] text-neutral-500">
          {zh ? "原文证据：" : "Original: "}{evidence.originalEvidence}
        </p>
      ) : null}
      <div className="mt-1.5 flex items-center justify-between gap-2 font-mono text-[9px] text-neutral-600">
        <span>{evidence.createdAt.slice(0, 10)} · {evidence.horizon || "unknown"}</span>
        <a
          href={evidence.url}
          target="_blank"
          rel="noreferrer"
          className="font-sans font-semibold text-reddit transition hover:text-cream"
        >
          {evidenceLinkLabel(evidence.source, zh)} ↗
        </a>
      </div>
    </article>
  );
}

function platformKeyOf(sources: SmartVoiceMarketSource[]): SmartVoiceMarketPlatformKey {
  if (sources.length === MARKET_SOURCES.length) return "all";
  const selected = new Set(sources);
  return MARKET_SOURCES.map((item) => item.key)
    .filter((source) => selected.has(source))
    .join("+") as SmartVoiceMarketPlatformKey;
}

export function SmartVoiceMarketView({
  marketData,
  zh,
}: {
  marketData: SmartVoiceMarketData;
  zh: boolean;
}) {
  const [windowKey, setWindowKey] = useState<SmartVoiceMarketWindow>("30D");
  const [sources, setSources] = useState<SmartVoiceMarketSource[]>(["x", "youtube", "reddit", "xueqiu"]);
  const [mode, setMode] = useState<MarketMode>("bullish");
  const [query, setQuery] = useState("");
  const [selectedTicker, setSelectedTicker] = useState("");
  const { boards, evidenceById } = marketData;
  const platformKey = platformKeyOf(sources);
  const rows = useMemo(() => {
    const q = query.trim().toUpperCase();
    return boards[platformKey][windowKey][mode].filter((row) => !q || row.ticker.includes(q) || row.nameZh.includes(query) || row.nameEn.toUpperCase().includes(q));
  }, [boards, mode, platformKey, query, windowKey]);
  const selected = rows.find((row) => row.ticker === selectedTicker) ?? rows[0];
  const color = selected ? metricColor(selected, mode) : MODE_META[mode].color;
  const selectedEvidence = selected ? evidenceGroups(selected, mode) : { primary: [], counter: [] };
  const primaryEvidence = selectedEvidence.primary
    .map((id) => evidenceById[id])
    .filter((item): item is SmartVoiceTickerEvidence => Boolean(item));
  const counterEvidence = selectedEvidence.counter
    .map((id) => evidenceById[id])
    .filter((item): item is SmartVoiceTickerEvidence => Boolean(item));

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
          <span>{mode === "contrast"
            ? (zh ? "高 / 低 SV 净方向" : "High / low-SV net")
            : mode === "authorShift" ? (zh ? "前期 → 本期净人数" : "Previous → current net") : (zh ? "Top 10% 作者方向" : "Top 10% direction")}</span>
          <span className="text-right" title={zh ? "每位 Top 10% 作者仅保留窗口内最新观点" : "Each Top 10% author contributes their latest call only"}>{mode === "contrast"
            ? (zh ? "高/低作者" : "High/low voices")
            : mode === "authorShift" ? (zh ? "净变化" : "Net change") : (zh ? "作者净人数" : "Net authors")}</span>
          <span className="text-right">{mode === "contrast" ? "Delta" : mode === "authorShift" ? (zh ? "突变幅度" : "Shift") : (zh ? "净强度" : "Net strength")}</span>
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
                  {mode === "contrast" ? (
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
                {mode === "contrast" ? (
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

      <aside data-testid="smart-voice-market-detail" className="min-h-0 overflow-y-auto border-l border-line bg-white/[.012] p-4">
        {selected ? (
          <div className="flex min-h-full flex-col">
            <div className="flex items-start gap-3">
              <TickerLogo ticker={selected.ticker} size={38} />
              <div className="min-w-0 flex-1">
                <div className="font-mono text-[18px] font-bold leading-none text-cream">{selected.ticker}</div>
                <div className="mt-1 truncate text-[11px] text-neutral-500">{zh ? selected.nameZh : selected.nameEn}</div>
                <div className="mt-1 font-mono text-[9px] text-neutral-700">{windowKey} · {sources.join("+")} · {marketData.latestAt.slice(0, 16)} UTC</div>
              </div>
              <div className="text-right">
                <div className="text-[9px] uppercase tracking-[0.12em] text-neutral-600">
                  {mode === "contrast" ? "Delta" : mode === "authorShift" ? (zh ? "突变幅度" : "Author shift") : (zh ? "高 SV 净强度" : "High-SV net")}
                </div>
                <div className="mt-1 font-mono text-[22px] font-bold leading-none" style={{ color }}>{metricText(selected, mode)}</div>
              </div>
            </div>

            <div className="mt-5 border-y border-line py-3">
              <div className="flex items-center justify-between text-[11px]">
                <span className="text-neutral-500">{mode === "contrast"
                  ? (zh ? "分歧关系" : "Divergence")
                  : mode === "authorShift" ? (zh ? "作者净人数变化" : "Net-author change") : (zh ? "Top 10% 作者方向" : "Top 10% direction")}</span>
                <span className={`font-semibold ${mode === "authorShift" && selected.authorNetAbrupt ? "text-[#8CBBFF]" : "text-cream"}`}>
                  {mode === "authorShift" ? (selected.authorNetAbrupt ? (zh ? "发生突变" : "Abrupt shift") : (zh ? "一般变化" : "Normal change")) : signalLabel(selected.signal, zh)}
                </span>
              </div>
              {mode === "contrast" ? (
                <div className="mt-3 grid grid-cols-2 gap-3 font-mono text-[10.5px]">
                  <div><span className="text-neutral-600">Top 10%</span><div className={`mt-1 text-[14px] font-bold ${selected.highNet >= 0 ? "text-bull" : "text-bear"}`}>{signed(selected.highNet)}</div></div>
                  <div><span className="text-neutral-600">Bottom 10%</span><div className={`mt-1 text-[14px] font-bold ${selected.lowNet >= 0 ? "text-bull" : "text-bear"}`}>{signed(selected.lowNet)}</div></div>
                </div>
              ) : mode === "authorShift" ? (
                <div className="mt-3 grid grid-cols-3 gap-3 font-mono text-[10.5px]">
                  <div>
                    <span className="text-neutral-600">{zh ? "前一窗口" : "Previous"}</span>
                    <div className={`mt-1 text-[14px] font-bold ${selected.previousHighAuthorNet >= 0 ? "text-bull" : "text-bear"}`}>{signedInteger(selected.previousHighAuthorNet)}</div>
                    <div className="mt-0.5 text-[8.5px] text-neutral-700">{selected.previousHighAuthorBullCount}/{selected.previousHighAuthorBearCount}</div>
                  </div>
                  <div>
                    <span className="text-neutral-600">{zh ? "当前窗口" : "Current"}</span>
                    <div className={`mt-1 text-[14px] font-bold ${selected.highAuthorNet >= 0 ? "text-bull" : "text-bear"}`}>{signedInteger(selected.highAuthorNet)}</div>
                    <div className="mt-0.5 text-[8.5px] text-neutral-700">{selected.highAuthorBullCount}/{selected.highAuthorBearCount}</div>
                  </div>
                  <div>
                    <span className="text-neutral-600">{zh ? "变化排名" : "Change rank"}</span>
                    <div className="mt-1 text-[14px] font-bold text-[#8CBBFF]">#{selected.authorNetShiftRank}</div>
                    <div className={`mt-0.5 text-[8.5px] ${selected.authorNetDelta >= 0 ? "text-bull" : "text-bear"}`}>Δ {signedInteger(selected.authorNetDelta)}</div>
                  </div>
                </div>
              ) : (
                <>
                  <div className="mt-3 flex h-2 overflow-hidden rounded-full bg-bear/80">
                    <div className="h-full bg-bull" style={{ width: `${highRatio(selected)}%` }} />
                  </div>
                  <div className="mt-1.5 flex items-center justify-between font-mono text-[10.5px]">
                    <span className="text-bull">{zh ? "看多" : "Bull"} {selected.highBullCalls}</span>
                    <span className="text-bear">{zh ? "看空" : "Bear"} {selected.highBearCalls}</span>
                  </div>
                </>
              )}
            </div>

            <div className="py-4">
              <div className="flex items-center justify-between gap-3 text-[9.5px]">
                <span className="font-semibold uppercase tracking-[0.1em] text-neutral-500">{mode === "authorShift" ? (zh ? "当前窗口作者人数" : "Current author headcount") : (zh ? "作者人数口径" : "Author headcount")}</span>
                <span className="text-neutral-700">{mode === "authorShift" ? (zh ? "与前一等长窗口比较" : "Compared with prior equal window") : (zh ? "每位作者最新观点 · 不参与当前排序" : "Latest call per author · not ranked")}</span>
              </div>
              <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-3 text-[11px]">
              <div>
                <dt className="text-neutral-600">{zh ? "看多作者" : "Bull authors"}</dt>
                <dd className="mt-1 font-mono text-[16px] font-bold text-bull">{selected.highAuthorBullCount}</dd>
              </div>
              <div>
                <dt className="text-neutral-600">{zh ? "看空作者" : "Bear authors"}</dt>
                <dd className="mt-1 font-mono text-[16px] font-bold text-bear">{selected.highAuthorBearCount}</dd>
              </div>
              <div>
                <dt className="text-neutral-600">{zh ? "作者净人数" : "Net authors"}</dt>
                <dd className={`mt-1 font-mono text-[16px] font-bold ${selected.highAuthorNet >= 0 ? "text-bull" : "text-bear"}`}>{signedInteger(selected.highAuthorNet)}</dd>
              </div>
              <div>
                <dt className="text-neutral-600">{zh ? "作者共识度" : "Author consensus"}</dt>
                <dd className={`mt-1 font-mono text-[16px] font-bold ${selected.highAuthorConsensus >= 0 ? "text-bull" : "text-bear"}`}>{selected.highAuthorConsensus > 0 ? "+" : ""}{selected.highAuthorConsensus.toFixed(1)}%</dd>
              </div>
              <div>
                <dt className="text-neutral-600">{zh ? "看多加权" : "Bull weight"}</dt>
                <dd className="mt-1 font-mono text-[16px] font-bold text-bull">{selected.highBullScore.toFixed(1)}</dd>
              </div>
              <div>
                <dt className="text-neutral-600">{zh ? "看空加权" : "Bear weight"}</dt>
                <dd className="mt-1 font-mono text-[16px] font-bold text-bear">{selected.highBearScore.toFixed(1)}</dd>
              </div>
              </dl>
            </div>

            <div className="border-t border-line pt-3">
              <div className="text-[10px] font-semibold uppercase tracking-[0.1em] text-neutral-500">{zh ? "为什么入榜" : "Why it ranks"}</div>
              <p className="mt-1.5 text-[10.5px] leading-[1.55] text-neutral-400">
                {mode === "contrast"
                  ? (zh
                    ? `Top 10% 作者净方向 ${signed(selected.highNet)}，Bottom 10% 作者净方向 ${signed(selected.lowNet)}，两组方向相反。`
                    : `Top 10% net is ${signed(selected.highNet)} while Bottom 10% net is ${signed(selected.lowNet)}; the groups point in opposite directions.`)
                  : mode === "authorShift"
                    ? (zh
                      ? `前一${windowKey}作者净人数 ${signedInteger(selected.previousHighAuthorNet)}，当前${windowKey}为 ${signedInteger(selected.highAuthorNet)}，净变化 ${signedInteger(selected.authorNetDelta)}；按两期较大作者规模归一化后，突变幅度为 ${metricText(selected, mode)}。`
                      : `Net authors moved from ${signedInteger(selected.previousHighAuthorNet)} in the prior ${windowKey} to ${signedInteger(selected.highAuthorNet)} now, a ${signedInteger(selected.authorNetDelta)} change and ${metricText(selected, mode)} normalized shift.`)
                  : (zh
                    ? `Top 10% 作者中有 ${selected.highBullCalls} 条看多、${selected.highBearCalls} 条看空；看多加权 ${selected.highBullScore.toFixed(1)}，看空加权 ${selected.highBearScore.toFixed(1)}，净方向 ${signed(selected.highNet)}。`
                    : `Top 10% voices made ${selected.highBullCalls} bull and ${selected.highBearCalls} bear calls. Bull weight is ${selected.highBullScore.toFixed(1)}, bear weight is ${selected.highBearScore.toFixed(1)}, for a ${signed(selected.highNet)} net.`)}
              </p>
              {mode === "authorShift" ? (
                <p className="mt-2 border-l-2 border-[#6EA8FE]/30 pl-2 text-[10px] leading-[1.5] text-neutral-500">
                  {zh
                    ? `突变判定：|净人数变化| ≥ 3、|突变幅度| ≥ 50%，且前后两个窗口都至少有 3 位作者。当前${selected.authorNetAbrupt ? "达到" : "未达到"}阈值。`
                    : `Abrupt when |net change| ≥ 3, |shift| ≥ 50%, and both windows contain at least 3 authors. This ticker ${selected.authorNetAbrupt ? "meets" : "does not meet"} the threshold.`}
                </p>
              ) : mode !== "contrast" ? (
                <p className="mt-2 border-l-2 border-white/10 pl-2 text-[10px] leading-[1.5] text-neutral-500">
                  {zh
                    ? `按每位作者的最新观点去重后：${selected.highAuthorBullCount} 人看多、${selected.highAuthorBearCount} 人看空，作者净人数 ${signedInteger(selected.highAuthorNet)}，共识度 ${selected.highAuthorConsensus > 0 ? "+" : ""}${selected.highAuthorConsensus.toFixed(1)}%。`
                    : `Using each author's latest call: ${selected.highAuthorBullCount} bull, ${selected.highAuthorBearCount} bear, net authors ${signedInteger(selected.highAuthorNet)}, consensus ${selected.highAuthorConsensus > 0 ? "+" : ""}${selected.highAuthorConsensus.toFixed(1)}%.`}
                </p>
              ) : null}
            </div>

            <div className="mt-4 border-t border-line pt-3">
              <div className="flex items-center justify-between gap-3">
                <div className="text-[10px] font-semibold uppercase tracking-[0.1em] text-neutral-500">
                  {mode === "contrast"
                    ? (zh ? "高 SV 证据" : "High-SV evidence")
                    : mode === "authorShift" ? (zh ? "当前窗口代表证据" : "Current-window evidence")
                      : mode === "bullish" ? (zh ? "代表性看多证据" : "Representative bull evidence") : (zh ? "代表性看空证据" : "Representative bear evidence")}
                </div>
                <span className="text-[9px] text-neutral-700">{zh ? "可打开原始来源" : "Traceable sources"}</span>
              </div>
              <div className="mt-1">
                {primaryEvidence.map((evidence) => <EvidenceItem key={evidence.id} evidence={evidence} zh={zh} />)}
                {mode === "authorShift" && !primaryEvidence.length ? <p className="py-3 text-[10px] text-neutral-600">{zh ? "当前窗口没有可展示的 Top 10% 作者观点。" : "No current-window Top 10% evidence."}</p> : null}
              </div>
            </div>

            {counterEvidence.length ? (
              <div className="mt-3 border-t border-line pt-3">
                <div className="text-[10px] font-semibold uppercase tracking-[0.1em] text-neutral-600">
                  {mode === "contrast"
                    ? (zh ? "低 SV 反向证据" : "Low-SV counter evidence")
                    : mode === "authorShift" ? (zh ? "前一窗口代表证据" : "Previous-window evidence") : (zh ? "反方证据" : "Counter evidence")}
                </div>
                <div className="mt-1">
                  {counterEvidence.slice(0, 2).map((evidence) => <EvidenceItem key={evidence.id} evidence={evidence} zh={zh} />)}
                </div>
              </div>
            ) : null}

            <LocaleLink href={`/tickers/${selected.ticker}`} className="mt-4 flex h-9 shrink-0 items-center justify-center rounded-lg bg-reddit text-[12px] font-bold text-[#12201d] transition hover:brightness-110">
              {zh ? "查看标的详情" : "Open ticker"}
            </LocaleLink>
          </div>
        ) : null}
      </aside>
    </div>
  );
}
