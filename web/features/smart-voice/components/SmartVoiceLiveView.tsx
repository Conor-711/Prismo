"use client";

import { useMemo, useState } from "react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { smartVoiceInvestorHref } from "@/features/smart-voice/svInvestorLinks";
import { TickerLogo } from "@/shared/market/TickerLogo";
import type { SmartVoiceLiveCall } from "@/server/queries/smartVoiceQueries";

type SourceFilter = "all" | "x" | "youtube" | "reddit" | "xueqiu";
type DirectionFilter = "all" | "bull" | "bear";

const SOURCE_META: Record<string, { label: string; color: string }> = {
  x: { label: "X", color: "#8C96A2" },
  youtube: { label: "YouTube", color: "#E0A33E" },
  reddit: { label: "Reddit", color: "#E07A55" },
  xueqiu: { label: "雪球", color: "#5BA3C4" },
};

const STYLE_LABEL: Record<string, [string, string]> = {
  technical: ["技术分析", "Technical"],
  fundamental: ["基本面", "Fundamental"],
  event_driven: ["事件驱动", "Event driven"],
  macro: ["宏观", "Macro"],
  flow_momentum: ["资金流 / 动量", "Flow / momentum"],
  mixed: ["混合", "Mixed"],
  unknown: ["未分类", "Unknown"],
};

function sourceMeta(source: string) {
  return SOURCE_META[source] ?? { label: source || "Other", color: "#8C96A2" };
}

function cleanHandle(handle: string) {
  return handle.replace(/^@+/, "");
}

function dayTime(value: string) {
  return value ? value.slice(5, 16).replace("T", " ") : "—";
}

function horizonLabel(horizon: string, zh: boolean) {
  return horizon === "unknown" ? (zh ? "未注明" : "Unspecified") : horizon;
}

export function SmartVoiceLiveView({
  calls,
  profileIds,
  zh,
}: {
  calls: SmartVoiceLiveCall[];
  profileIds: string[];
  zh: boolean;
}) {
  const [source, setSource] = useState<SourceFilter>("all");
  const [direction, setDirection] = useState<DirectionFilter>("all");
  const [query, setQuery] = useState("");
  const [selectedId, setSelectedId] = useState("");
  const profileSet = useMemo(() => new Set(profileIds), [profileIds]);
  const rows = useMemo(() => {
    const q = query.trim().toLowerCase();
    return calls.filter((call) => {
      if (source !== "all" && call.source !== source) return false;
      if (direction !== "all" && call.direction !== direction) return false;
      if (!q) return true;
      return call.ticker.toLowerCase().includes(q)
        || call.author.toLowerCase().includes(q)
        || call.summaryZh.toLowerCase().includes(q)
        || call.summaryEn.toLowerCase().includes(q);
    });
  }, [calls, direction, query, source]);
  const selected = rows.find((call) => call.id === selectedId) ?? rows[0];

  return (
    <div className="grid h-full min-h-0 lg:grid-cols-[minmax(0,1fr)_320px] xl:grid-cols-[minmax(0,1fr)_380px]">
      <section className="flex min-h-0 min-w-0 flex-col">
        <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-line px-3 py-2.5">
          <div className="inline-flex h-8 items-center rounded-lg bg-white/[.025] p-0.5 ring-1 ring-inset ring-line">
            {(["all", "x", "youtube", "reddit", "xueqiu"] as SourceFilter[]).map((key) => (
              <button
                key={key}
                type="button"
                onClick={() => {
                  setSource(key);
                  setSelectedId("");
                }}
                className={`h-7 rounded-md px-3 text-[11.5px] font-semibold transition ${source === key ? "bg-reddit/12 text-reddit ring-1 ring-inset ring-reddit/30" : "text-neutral-500 hover:text-cream"}`}
              >
                {key === "all" ? (zh ? "全部来源" : "All sources") : sourceMeta(key).label}
              </button>
            ))}
          </div>
          <div className="inline-flex h-8 items-center rounded-lg p-0.5 ring-1 ring-inset ring-line">
            {(["all", "bull", "bear"] as DirectionFilter[]).map((key) => (
              <button
                key={key}
                type="button"
                onClick={() => {
                  setDirection(key);
                  setSelectedId("");
                }}
                className={`h-7 rounded-md px-2.5 text-[11px] font-semibold transition ${direction === key ? (key === "bull" ? "bg-bull/10 text-bull ring-1 ring-inset ring-bull/25" : key === "bear" ? "bg-bear/10 text-bear ring-1 ring-inset ring-bear/25" : "bg-white/[.06] text-cream ring-1 ring-inset ring-white/10") : "text-neutral-500 hover:text-cream"}`}
              >
                {key === "all" ? (zh ? "全部方向" : "All") : key === "bull" ? (zh ? "看多" : "Bull") : (zh ? "看空" : "Bear")}
              </button>
            ))}
          </div>
          <label className="ml-auto flex h-8 min-w-[190px] max-w-[320px] flex-1 items-center gap-2 rounded-lg px-2.5 ring-1 ring-inset ring-line focus-within:ring-reddit/50">
            <span aria-hidden className="text-[13px] text-neutral-600">⌕</span>
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder={zh ? "搜索标的、作者或观点" : "Search ticker, voice or call"}
              className="min-w-0 flex-1 bg-transparent text-[12px] text-cream outline-none placeholder:text-neutral-700"
            />
          </label>
        </div>

        <div className="grid shrink-0 grid-cols-[84px_76px_110px_minmax(220px,1fr)_70px_58px] items-center gap-3 border-b border-line bg-white/[.015] px-3 py-2 text-[10px] font-semibold uppercase tracking-[0.08em] text-neutral-600">
          <span>{zh ? "时间" : "Time"}</span>
          <span>{zh ? "标的" : "Ticker"}</span>
          <span>{zh ? "作者" : "Voice"}</span>
          <span>{zh ? "有效观点" : "Actionable call"}</span>
          <span>{zh ? "周期" : "Horizon"}</span>
          <span className="text-right">SV</span>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto">
          {rows.map((call) => {
            const meta = sourceMeta(call.source);
            const active = selected?.id === call.id;
            return (
              <button
                key={call.id}
                type="button"
                onClick={() => setSelectedId(call.id)}
                className={`grid w-full grid-cols-[84px_76px_110px_minmax(220px,1fr)_70px_58px] items-center gap-3 border-b border-line/70 px-3 py-2.5 text-left transition ${active ? "bg-reddit/[.055] shadow-[inset_2px_0_0_#57D7BA]" : "hover:bg-white/[.025]"}`}
              >
                <span className="font-mono text-[10.5px] text-neutral-600">{dayTime(call.createdAt)}</span>
                <span className="flex items-center gap-2">
                  <TickerLogo ticker={call.ticker} size={24} />
                  <span className="font-mono text-[12px] font-bold text-cream">{call.ticker}</span>
                </span>
                <span className="min-w-0">
                  <span className="block truncate text-[11px] font-semibold text-neutral-300">@{cleanHandle(call.author)}</span>
                  <span className="mt-0.5 block text-[9.5px]" style={{ color: meta.color }}>{meta.label}</span>
                </span>
                <span className="min-w-0">
                  <span className="flex items-center gap-2">
                    <span className={`h-1.5 w-1.5 shrink-0 rounded-full ${call.direction === "bull" ? "bg-bull" : "bg-bear"}`} />
                    <span className="truncate text-[11.5px] text-neutral-300">{zh ? call.summaryZh || call.summaryEn : call.summaryEn || call.summaryZh}</span>
                  </span>
                  {call.targetPrice ? <span className={`mt-0.5 block pl-3.5 font-mono text-[9.5px] ${call.direction === "bull" ? "text-bull" : "text-bear"}`}>{zh ? "目标" : "Target"} ${call.targetPrice.toLocaleString("en-US")}</span> : null}
                </span>
                <span className="font-mono text-[10.5px] text-neutral-500">{horizonLabel(call.horizon, zh)}</span>
                <span className={`text-right font-mono text-[14px] font-bold ${call.sv >= 115 ? "text-bull" : call.sv < 95 ? "text-bear" : "text-cream"}`}>{call.sv}</span>
              </button>
            );
          })}
          {!rows.length ? <div className="grid h-full place-items-center text-[12px] text-neutral-600">{zh ? "没有匹配的实时观点" : "No matching live calls"}</div> : null}
        </div>
      </section>

      <aside className="min-h-0 overflow-y-auto border-l border-line bg-white/[.012] p-4">
        {selected ? (
          <div className="flex min-h-full flex-col">
            <div className="flex items-start gap-3">
              <TickerLogo ticker={selected.ticker} size={38} />
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="font-mono text-[18px] font-bold leading-none text-cream">{selected.ticker}</span>
                  <span className={`rounded-md px-2 py-0.5 text-[10px] font-bold ring-1 ring-inset ${selected.direction === "bull" ? "bg-bull/10 text-bull ring-bull/25" : "bg-bear/10 text-bear ring-bear/25"}`}>{selected.direction === "bull" ? (zh ? "看多" : "Bull") : (zh ? "看空" : "Bear")}</span>
                </div>
                <div className="mt-1 truncate text-[11px] text-neutral-500">{zh ? selected.nameZh : selected.nameEn}</div>
              </div>
              <div className="text-right">
                <div className="text-[9px] uppercase tracking-[0.14em] text-neutral-600">SV</div>
                <div className={`mt-1 font-mono text-[24px] font-bold leading-none ${selected.sv >= 115 ? "text-bull" : selected.sv < 95 ? "text-bear" : "text-cream"}`}>{selected.sv}</div>
              </div>
            </div>

            <div className="mt-4 border-y border-line py-3">
              <div className="flex items-center justify-between gap-3 text-[11px]">
                <span className="truncate font-semibold text-cream">@{cleanHandle(selected.author)}</span>
                <span style={{ color: sourceMeta(selected.source).color }}>{sourceMeta(selected.source).label}</span>
              </div>
              <div className="mt-1.5 flex items-center justify-between text-[10px] text-neutral-600">
                <span>{STYLE_LABEL[selected.investorStyle]?.[zh ? 0 : 1] ?? selected.investorStyle}</span>
                <span className="font-mono">{dayTime(selected.createdAt)}</span>
              </div>
            </div>

            <div className="py-4">
              <div className="text-[10px] font-semibold uppercase tracking-[0.1em] text-neutral-600">{zh ? "观点摘要" : "Call summary"}</div>
              <p className="mt-2 text-[13px] leading-[1.65] text-neutral-200">{zh ? selected.summaryZh || selected.summaryEn : selected.summaryEn || selected.summaryZh}</p>
            </div>

            <dl className="grid grid-cols-2 gap-x-4 gap-y-3 border-t border-line py-4 text-[11px]">
              <div><dt className="text-neutral-600">{zh ? "观点周期" : "Horizon"}</dt><dd className="mt-1 font-mono font-semibold text-cream">{horizonLabel(selected.horizon, zh)}</dd></div>
              <div><dt className="text-neutral-600">{zh ? "观点权重" : "Call weight"}</dt><dd className="mt-1 font-mono font-semibold text-cream">{selected.callWeight.toFixed(2)}</dd></div>
              <div><dt className="text-neutral-600">{zh ? "置信等级" : "Confidence"}</dt><dd className="mt-1 font-semibold capitalize text-cream">{selected.confidence}</dd></div>
              <div><dt className="text-neutral-600">{zh ? "目标价" : "Target"}</dt><dd className={`mt-1 font-mono font-semibold ${selected.targetPrice ? (selected.direction === "bull" ? "text-bull" : "text-bear") : "text-neutral-600"}`}>{selected.targetPrice ? `$${selected.targetPrice.toLocaleString("en-US")}` : "—"}</dd></div>
            </dl>

            <div className="mt-auto grid grid-cols-2 gap-2">
              {profileSet.has(selected.investorId) ? (
                <LocaleLink href={smartVoiceInvestorHref(selected.investorId)} className="flex h-9 items-center justify-center rounded-lg text-[11.5px] font-bold text-reddit ring-1 ring-inset ring-reddit/35 transition hover:bg-reddit/10">
                  {zh ? "作者画像" : "Voice profile"}
                </LocaleLink>
              ) : <span />}
              {selected.url ? (
                <a href={selected.url} target="_blank" rel="noopener noreferrer" className="flex h-9 items-center justify-center rounded-lg bg-reddit text-[11.5px] font-bold text-[#12201d] transition hover:brightness-110">
                  {zh ? "查看原帖 ↗" : "Open source ↗"}
                </a>
              ) : null}
            </div>
          </div>
        ) : null}
      </aside>
    </div>
  );
}
