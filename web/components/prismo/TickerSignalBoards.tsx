"use client";

import { useState } from "react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { TickerLogo } from "./TickerLogo";
import { StanceBar } from "./Bits";
import { fmtCompact } from "@/lib/format";
import type { KolRank, KolSwing } from "@/lib/kolQueries";
import type { SmartVoiceTickerRank } from "@/lib/smartVoiceQueries";

const GREEN = "#57D7BA";
const RED = "#FF5C6C";
const AMBER = "#F2B544";

function KolRow({ r, rank, zh }: { r: KolRank; rank: number; zh: boolean }) {
  const name = zh ? r.nameZh || r.nameEn : r.nameEn || r.nameZh;
  const netColor = r.net > 0 ? GREEN : r.net < 0 ? RED : "#9aa0a6";
  return (
    <li>
      <LocaleLink href={`/tickers/${r.ticker}`} className="flex items-center gap-3 rounded-lg px-2 py-2 transition hover:bg-elevated/60">
        <span className="w-4 shrink-0 text-center font-mono text-[12px] tabular text-neutral-600">{rank}</span>
        <TickerLogo ticker={r.ticker} size={26} />
        <div className="min-w-0 flex-1">
          <div className="flex items-baseline gap-1.5">
            <span className="font-mono text-[13px] font-semibold text-cream">{r.ticker}</span>
            <span className="min-w-0 truncate text-[11px] text-neutral-500">{name}</span>
          </div>
          <div className="mt-1 flex items-center gap-2">
            <StanceBar bull={r.nBull} bear={r.nBear} neutral={0} className="max-w-[120px] flex-1" />
            <span className="shrink-0 text-[10px] tabular text-neutral-600">
              <span style={{ color: GREEN }}>{fmtCompact(r.nBull)}</span>
              {" · "}
              <span style={{ color: RED }}>{fmtCompact(r.nBear)}</span>
            </span>
          </div>
        </div>
        <span className="shrink-0 text-right font-mono text-[14px] font-bold tabular" style={{ color: netColor }}>
          {r.net > 0 ? "+" : ""}{fmtCompact(r.net)}
        </span>
      </LocaleLink>
    </li>
  );
}

function SvRow({ r, rank, zh, metric }: { r: SmartVoiceTickerRank; rank: number; zh: boolean; metric: "bull" | "bear" | "contrast" }) {
  const name = zh ? r.nameZh || r.nameEn : r.nameEn || r.nameZh;
  const main = metric === "bull" ? r.bullScore : metric === "bear" ? r.bearScore : r.contrastScore;
  const color = metric === "bull" ? GREEN : metric === "bear" ? RED : AMBER;
  const signalLabel: Record<SmartVoiceTickerRank["signal"], string> = {
    high_bull_low_bear: zh ? "高 SV 看多 · 低 SV 看空" : "High-SV bull · low-SV bear",
    high_bear_low_bull: zh ? "高 SV 看空 · 低 SV 看多" : "High-SV bear · low-SV bull",
    sv_consensus_bull: zh ? "高 SV 共识偏多" : "High-SV bullish consensus",
    sv_consensus_bear: zh ? "高 SV 共识偏空" : "High-SV bearish consensus",
    mixed: zh ? "高低 SV 分歧" : "SV divergence",
  };
  return (
    <li>
      <LocaleLink href={`/tickers/${r.ticker}`} className="flex items-center gap-3 rounded-lg px-2 py-2 transition hover:bg-elevated/60">
        <span className="w-4 shrink-0 text-center font-mono text-[12px] tabular text-neutral-600">{rank}</span>
        <TickerLogo ticker={r.ticker} size={26} />
        <div className="min-w-0 flex-1">
          <div className="flex items-baseline gap-1.5">
            <span className="font-mono text-[13px] font-semibold text-cream">{r.ticker}</span>
            <span className="min-w-0 truncate text-[11px] text-neutral-500">{name}</span>
          </div>
          <div className="mt-1 flex items-center gap-2">
            <StanceBar bull={r.bullScore} bear={r.bearScore} neutral={0} className="max-w-[120px] flex-1" />
            <span className="shrink-0 text-[10px] tabular text-neutral-600">
              <span style={{ color: GREEN }}>{r.nBull}</span>
              {" · "}
              <span style={{ color: RED }}>{r.nBear}</span>
            </span>
          </div>
          <div className="mt-0.5 truncate text-[10px] text-neutral-600">
            {metric === "contrast" ? signalLabel[r.signal] : r.topHandles.slice(0, 2).map((h) => `@${h}`).join(" · ")}
          </div>
        </div>
        <span className="shrink-0 text-right">
          <span className="font-mono text-[14px] font-bold tabular" style={{ color }}>
            {metric === "contrast" ? "Δ" : ""}{main.toFixed(1)}
          </span>
          <span className="block text-[10px] text-neutral-600">SV</span>
        </span>
      </LocaleLink>
    </li>
  );
}

function Shell({ title, hint, icon, color, children }: { title: string; hint: string; icon: string; color: string; children: React.ReactNode }) {
  return (
    <div className="rounded-xl bg-card p-4 ring-1 ring-inset ring-line">
      <div className="mb-2 flex items-center gap-2">
        <span aria-hidden className="grid h-5 w-5 place-items-center rounded-md text-[12px] font-bold" style={{ background: `${color}22`, color }}>
          {icon}
        </span>
        <span className="text-[13px] font-semibold text-cream">{title}</span>
        <span className="ml-auto text-[10px] text-neutral-600">{hint}</span>
      </div>
      {children}
    </div>
  );
}

function Empty({ zh }: { zh: boolean }) {
  return <p className="px-2 py-6 text-center text-[12px] text-neutral-600">{zh ? "暂无数据" : "No data yet"}</p>;
}

function SwingRow({ r, rank, zh }: { r: KolSwing; rank: number; zh: boolean }) {
  const name = zh ? r.nameZh || r.nameEn : r.nameEn || r.nameZh;
  const up = r.delta > 0;
  const dColor = up ? GREEN : RED;
  return (
    <li>
      <LocaleLink href={`/tickers/${r.ticker}`} className="flex items-center gap-3 rounded-lg px-2 py-2 transition hover:bg-elevated/60">
        <span className="w-4 shrink-0 text-center font-mono text-[12px] tabular text-neutral-600">{rank}</span>
        <TickerLogo ticker={r.ticker} size={26} />
        <div className="min-w-0 flex-1">
          <div className="flex items-baseline gap-1.5">
            <span className="font-mono text-[13px] font-semibold text-cream">{r.ticker}</span>
            <span className="min-w-0 truncate text-[11px] text-neutral-500">{name}</span>
          </div>
          <div className="mt-0.5 text-[10.5px] tabular text-neutral-600">
            {zh ? "看多占比 " : "bull "}
            <span className="text-neutral-400">{r.priorShare}%</span>
            <span className="px-1 text-neutral-600">→</span>
            <span style={{ color: dColor }}>{r.recentShare}%</span>
          </div>
        </div>
        <span className="shrink-0 text-right">
          <span className="font-mono text-[14px] font-bold tabular" style={{ color: dColor }}>
            {up ? "+" : ""}{r.delta}pp
          </span>
          <span className="block text-[10px]" style={{ color: dColor }}>{up ? (zh ? "转多" : "→ bull") : (zh ? "转空" : "→ bear")}</span>
        </span>
      </LocaleLink>
    </li>
  );
}

export function TickerSignalBoards({
  kolBullish,
  kolBearish,
  kolSwings,
  svBullish,
  svBearish,
  svContrast,
}: {
  kolBullish: KolRank[];
  kolBearish: KolRank[];
  kolSwings: KolSwing[];
  svBullish: SmartVoiceTickerRank[];
  svBearish: SmartVoiceTickerRank[];
  svContrast: SmartVoiceTickerRank[];
}) {
  const { lang } = useLocale();
  const zh = lang === "zh";
  const [mode, setMode] = useState<"kol" | "sv">("kol");
  const hasKol = kolBullish.length || kolBearish.length || kolSwings.length;
  const hasSv = svBullish.length || svBearish.length || svContrast.length;
  if (!hasKol && !hasSv) return null;

  return (
    <section className="rounded-xl bg-panel/40 p-3 ring-1 ring-inset ring-line">
      <div className="mb-3 flex flex-wrap items-center justify-between gap-3 px-1">
        <div>
          <div className="text-[10px] font-bold uppercase tracking-[0.16em] text-reddit">Signal Mode</div>
          <h2 className="mt-1 font-display text-[17px] font-extrabold leading-none text-cream">
            {zh ? "标的信号" : "Ticker signals"}
          </h2>
        </div>
        <div className="inline-flex rounded-lg bg-white/[.035] p-1 ring-1 ring-inset ring-line">
          {[
            ["kol", zh ? "KOL 观点" : "KOL views"],
            ["sv", "Smart Voice"],
          ].map(([key, label]) => (
            <button
              key={key}
              type="button"
              onClick={() => setMode(key as "kol" | "sv")}
              className={`rounded-md px-3 py-1.5 text-[12px] font-bold transition ${
                mode === key ? "bg-reddit/15 text-reddit ring-1 ring-inset ring-reddit/35" : "text-neutral-500 hover:text-cream"
              }`}
            >
              {label}
            </button>
          ))}
        </div>
      </div>

      {mode === "kol" ? (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <Shell title={zh ? "KOL 最看多" : "Most bullish (KOL)"} hint={zh ? "近 14 天 · 净情绪" : "14d · net sentiment"} icon="▲" color={GREEN}>
            {kolBullish.length ? <ol className="-mx-2">{kolBullish.map((r, i) => <KolRow key={r.ticker} r={r} rank={i + 1} zh={zh} />)}</ol> : <Empty zh={zh} />}
          </Shell>
          <Shell title={zh ? "KOL 最看空" : "Most bearish (KOL)"} hint={zh ? "近 14 天 · 净情绪" : "14d · net sentiment"} icon="▼" color={RED}>
            {kolBearish.length ? <ol className="-mx-2">{kolBearish.map((r, i) => <KolRow key={r.ticker} r={r} rank={i + 1} zh={zh} />)}</ol> : <Empty zh={zh} />}
          </Shell>
          <Shell title={zh ? "KOL 情绪变化最大" : "Biggest mood shift (KOL)"} hint={zh ? "近 14 天 · 看多占比 Δ" : "14d · Δ bull-share"} icon="⇅" color={AMBER}>
            {kolSwings.length ? <ol className="-mx-2">{kolSwings.map((r, i) => <SwingRow key={r.ticker} r={r} rank={i + 1} zh={zh} />)}</ol> : <Empty zh={zh} />}
          </Shell>
        </div>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <Shell title={zh ? "SV 看多最多" : "Most bullish (SV)"} hint={zh ? "高质量作者加权" : "weighted by author SV"} icon="▲" color={GREEN}>
            {svBullish.length ? <ol className="-mx-2">{svBullish.map((r, i) => <SvRow key={r.ticker} r={r} rank={i + 1} zh={zh} metric="bull" />)}</ol> : <Empty zh={zh} />}
          </Shell>
          <Shell title={zh ? "SV 看空最多" : "Most bearish (SV)"} hint={zh ? "高质量作者加权" : "weighted by author SV"} icon="▼" color={RED}>
            {svBearish.length ? <ol className="-mx-2">{svBearish.map((r, i) => <SvRow key={r.ticker} r={r} rank={i + 1} zh={zh} metric="bear" />)}</ol> : <Empty zh={zh} />}
          </Shell>
          <Shell title={zh ? "SV 反差最大" : "Largest SV contrast"} hint={zh ? "高低 SV 方向差" : "high vs low SV split"} icon="◇" color={AMBER}>
            {svContrast.length ? <ol className="-mx-2">{svContrast.map((r, i) => <SvRow key={r.ticker} r={r} rank={i + 1} zh={zh} metric="contrast" />)}</ol> : <Empty zh={zh} />}
          </Shell>
        </div>
      )}
    </section>
  );
}
