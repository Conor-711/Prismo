"use client";

import { useMemo, useState } from "react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { Panel } from "@/components/ui";
import { fmtCompact } from "@/lib/format";
import {
  NARRATIVE_LABELS,
  SV_HORIZONS,
  getPortfolioSmartVoice,
  investorTickerSv,
  type SvBoard,
  type SvConfidence,
  type SvHorizon,
  type SvInvestor,
  type SvTickerBoard,
} from "@/lib/svMock";
import { Avatar, SOURCE } from "./kolShared";

const ACCENT = "#57D7BA";
const LINE = "#2a2d2f";

function confidenceLabel(c: SvConfidence, zh: boolean) {
  if (c === "high") return zh ? "高置信" : "High confidence";
  if (c === "medium") return zh ? "中置信" : "Medium confidence";
  if (c === "low") return zh ? "低置信" : "Low confidence";
  return zh ? "观察中" : "Observing";
}

function svTone(score: number) {
  if (score >= 120) return "text-bull";
  if (score >= 105) return "text-cream";
  if (score >= 95) return "text-neutral-400";
  return "text-bear";
}

function sourceLabel(source: SvInvestor["source"]) {
  return source === "youtube" ? "YouTube" : "X";
}

export function SmartVoiceScore({
  score,
  label = "SV",
  size = "md",
}: {
  score: number;
  label?: string;
  size?: "sm" | "md" | "lg";
}) {
  const text = size === "lg" ? "text-[30px]" : size === "sm" ? "text-[18px]" : "text-[22px]";
  return (
    <div className="text-right">
      <div className="text-[9.5px] font-bold uppercase tracking-[0.16em] text-neutral-600">{label}</div>
      <div className={`font-display font-extrabold leading-none tabular ${text} ${svTone(score)}`}>{score}</div>
    </div>
  );
}

function SegmentBar({ value, max = 145 }: { value: number; max?: number }) {
  const width = Math.max(4, Math.min(100, ((value - 80) / (max - 80)) * 100));
  return (
    <div className="h-1.5 overflow-hidden rounded-full bg-white/[.06]">
      <div className="h-full rounded-full bg-reddit" style={{ width: `${width}%` }} />
    </div>
  );
}

function InvestorIdentity({ inv, compact = false }: { inv: SvInvestor; compact?: boolean }) {
  const color = inv.source === "youtube" ? SOURCE.youtube.color : SOURCE.x.color;
  const content = (
    <>
      <Avatar src={inv.avatar} color={color} name={inv.name} size={compact ? 28 : 34} />
      <div className="min-w-0">
        <div className="truncate text-[13px] font-semibold leading-tight text-cream">{inv.name}</div>
        <div className="mt-0.5 flex items-center gap-1.5 text-[10.5px] text-neutral-500">
          <span className="rounded px-1.5 py-px font-medium" style={{ background: `${color}22`, color }}>
            {sourceLabel(inv.source)}
          </span>
          <span>{inv.language.toUpperCase()}</span>
        </div>
      </div>
    </>
  );

  return (
    <a href={inv.url} target="_blank" rel="noopener noreferrer" className="flex min-w-0 items-center gap-2.5 transition hover:opacity-85">
      {content}
    </a>
  );
}

function InvestorRow({
  inv,
  rank,
  zh,
  score,
  suffix,
}: {
  inv: SvInvestor;
  rank: number;
  zh: boolean;
  score?: number;
  suffix?: React.ReactNode;
}) {
  const displayScore = score ?? inv.sv;
  const rationale = zh ? inv.rationaleZh : inv.rationaleEn;
  return (
    <div className="grid grid-cols-[26px_minmax(0,1fr)_auto] items-center gap-3 border-b border-line/70 px-3 py-2.5 last:border-b-0">
      <div className="text-center font-mono text-[13px] font-bold tabular text-neutral-600">{rank}</div>
      <div className="min-w-0">
        <InvestorIdentity inv={inv} />
        <div className="mt-1 flex flex-wrap items-center gap-1">
          {inv.topTickers.slice(0, 4).map((t) => (
            <LocaleLink key={t} href={`/tickers/${t}`} className="rounded bg-white/[.04] px-1.5 py-px font-mono text-[10px] text-neutral-400 hover:text-cream">
              {t}
            </LocaleLink>
          ))}
          <span className="rounded bg-reddit/10 px-1.5 py-px text-[10px] text-reddit ring-1 ring-inset ring-reddit/15">
            {confidenceLabel(inv.confidence, zh)}
          </span>
        </div>
        <p className="mt-1 truncate text-[11.5px] text-neutral-500">{rationale}</p>
        {suffix}
      </div>
      <div className="shrink-0">
        <SmartVoiceScore score={displayScore} size="sm" />
      </div>
    </div>
  );
}

function SmallMetric({ label, value, tone = "text-cream" }: { label: string; value: string; tone?: string }) {
  return (
    <div className="rounded-lg bg-white/[.025] px-2.5 py-2 ring-1 ring-inset ring-white/[.06]">
      <div className="text-[9.5px] uppercase tracking-wide text-neutral-600">{label}</div>
      <div className={`mt-0.5 font-mono text-[13px] font-bold leading-none tabular ${tone}`}>{value}</div>
    </div>
  );
}

export function SmartVoiceLeaderboard({ board }: { board: SvBoard }) {
  const [tab, setTab] = useState<"global" | "x" | "youtube" | SvHorizon | "semis" | "ai_infra">("global");
  const { lang } = useLocale();
  const zh = lang === "zh";

  const items = useMemo(() => {
    const scored = board.investors.map((inv) => {
      let score = inv.sv;
      if (tab === "x" || tab === "youtube") score = inv.source === tab ? inv.platformScores[tab] ?? inv.sv : inv.sv - 14;
      else if (SV_HORIZONS.includes(tab as SvHorizon)) score = inv.horizonScores[tab as SvHorizon] ?? inv.sv - 10;
      else if (tab === "semis" || tab === "ai_infra") score = inv.narrativeScores[tab] ?? inv.sv - 12;
      return { inv, score };
    });
    return scored.sort((a, b) => b.score - a.score).slice(0, 8);
  }, [board.investors, tab]);

  const tabs: { key: typeof tab; zh: string; en: string }[] = [
    { key: "global", zh: "当前总分", en: "Global" },
    { key: "x", zh: "X", en: "X" },
    { key: "youtube", zh: "YouTube", en: "YouTube" },
    { key: "1D", zh: "1D", en: "1D" },
    { key: "5D", zh: "5D", en: "5D" },
    { key: "20D", zh: "20D", en: "20D" },
    { key: "semis", zh: "半导体", en: "Semis" },
    { key: "ai_infra", zh: "AI 基建", en: "AI infra" },
  ];

  return (
    <Panel className="overflow-hidden">
      <div className="flex flex-wrap items-start justify-between gap-3 border-b border-line px-4 py-3">
        <div>
          <div className="text-[10px] font-bold uppercase tracking-[0.16em] text-reddit">Smart Voice</div>
          <h2 className="mt-1 font-display text-[17px] font-extrabold leading-none text-cream">
            {zh ? "当前最值得参考的投资者" : "Most valuable voices right now"}
          </h2>
          <p className="mt-1.5 text-[12px] text-neutral-500">
            {zh ? "Mock SV：准确性为主，叙事热度用于当前市场权重。" : "Mock SV: accuracy first, narrative heat adjusts current-market relevance."}
          </p>
        </div>
        <div className="grid grid-cols-3 gap-2">
          <SmallMetric label={zh ? "中位数" : "Median"} value="100" />
          <SmallMetric label={zh ? "样本池" : "Pool"} value={`${board.investors.length}`} />
          <SmallMetric label={zh ? "平台" : "Platforms"} value="X/YT" tone="text-reddit" />
        </div>
      </div>

      <div className="border-b border-line px-4 py-2">
        <div className="flex flex-wrap gap-1.5">
          {tabs.map((x) => (
            <button
              key={x.key}
              type="button"
              onClick={() => setTab(x.key)}
              className={`rounded-md px-2.5 py-1 text-[11.5px] font-semibold ring-1 ring-inset transition ${
                tab === x.key ? "bg-reddit/12 text-reddit ring-reddit/35" : "text-neutral-500 ring-line hover:text-cream"
              }`}
            >
              {zh ? x.zh : x.en}
            </button>
          ))}
        </div>
      </div>

      <div className="grid gap-0 lg:grid-cols-2">
        {items.map(({ inv, score }, i) => (
          <InvestorRow
            key={`${tab}:${inv.id}`}
            inv={inv}
            score={score}
            rank={i + 1}
            zh={zh}
            suffix={
              <div className="mt-1.5 grid grid-cols-4 gap-1.5">
                {SV_HORIZONS.map((h) => (
                  <div key={h}>
                    <div className="mb-0.5 flex justify-between text-[9.5px] text-neutral-600">
                      <span>{h}</span>
                      <span className="font-mono">{inv.horizonScores[h] ?? "—"}</span>
                    </div>
                    {typeof inv.horizonScores[h] === "number" && <SegmentBar value={inv.horizonScores[h] as number} />}
                  </div>
                ))}
              </div>
            }
          />
        ))}
      </div>

      <div className="flex flex-wrap items-center gap-2 border-t border-line px-4 py-2.5 text-[11px] text-neutral-500">
        <span>{zh ? "当前叙事权重" : "Current narrative weights"}</span>
        {board.currentNarratives.map((n) => (
          <span key={n.key} className="rounded bg-white/[.035] px-1.5 py-px text-neutral-400">
            {zh ? n.zh : n.en} <b className="font-mono text-reddit">{n.weight}%</b>
          </span>
        ))}
      </div>
    </Panel>
  );
}

export function SmartVoiceTickerModule({ board, zh }: { board: SvTickerBoard; zh: boolean }) {
  return (
    <div className="overflow-hidden rounded-xl bg-ink/35 ring-1 ring-inset ring-line">
      <div className="flex items-start justify-between gap-3 border-b border-line px-4 py-3">
        <div>
          <h3 className="font-display text-[14px] font-bold text-cream">
            {zh ? `${board.ticker} 最值得参考的 SV 投资者` : `Top SV voices for ${board.ticker}`}
          </h3>
          <p className="mt-1 text-[11.5px] text-neutral-500">
            {zh ? `按 ${board.narrative.zh} / 标的直接样本 / 当前市场权重排序` : `Ranked by ${board.narrative.en}, ticker samples and current-market relevance`}
          </p>
        </div>
        <span className="rounded-md bg-reddit/12 px-2 py-1 text-[11px] font-bold text-reddit ring-1 ring-inset ring-reddit/25">SV</span>
      </div>
      <div>
        {board.investors.map((inv, i) => (
          <InvestorRow
            key={inv.id}
            inv={inv}
            rank={i + 1}
            zh={zh}
            score={inv.contextualSv}
            suffix={
              <div className="mt-1 flex items-center justify-between gap-2 text-[10.5px] text-neutral-600">
                <span>{zh ? inv.basisZh : inv.basisEn}</span>
                <span className="font-mono tabular">{fmtCompact(inv.nEff)} n_eff · {inv.settledCalls} calls</span>
              </div>
            }
          />
        ))}
      </div>
    </div>
  );
}

export function SmartVoiceCreatorModule({ profile, zh }: { profile: SvInvestor; zh: boolean }) {
  const strongest = Object.entries(profile.narrativeScores).sort((a, b) => b[1] - a[1]).slice(0, 3);
  return (
    <Panel className="p-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <div className="text-[10px] font-bold uppercase tracking-[0.16em] text-reddit">Smart Voice</div>
          <h2 className="mt-1 font-display text-[15px] font-bold leading-none text-cream">
            {zh ? "作者 SV 画像" : "Creator SV profile"}
          </h2>
          <p className="mt-1.5 text-[12px] leading-relaxed text-neutral-500">{zh ? profile.rationaleZh : profile.rationaleEn}</p>
        </div>
        <SmartVoiceScore score={profile.sv} size="lg" />
      </div>
      <div className="mt-3 grid grid-cols-4 gap-2">
        {SV_HORIZONS.map((h) => (
          <SmallMetric key={h} label={h} value={profile.horizonScores[h] ? String(profile.horizonScores[h]) : "—"} tone={svTone(profile.horizonScores[h] ?? 100)} />
        ))}
      </div>
      <div className="mt-3 grid gap-2 sm:grid-cols-3">
        {strongest.map(([key, value]) => {
          const n = NARRATIVE_LABELS[key] ?? { zh: key, en: key };
          return (
            <div key={key} className="rounded-lg bg-white/[.025] p-2.5 ring-1 ring-inset ring-white/[.06]">
              <div className="truncate text-[11px] text-neutral-500">{zh ? n.zh : n.en}</div>
              <div className={`mt-1 font-display text-[18px] font-bold leading-none ${svTone(value)}`}>{value}</div>
              <SegmentBar value={value} />
            </div>
          );
        })}
      </div>
      <div className="mt-3 flex flex-wrap items-center gap-2 border-t border-line/70 pt-2 text-[11px] text-neutral-500">
        <span>{confidenceLabel(profile.confidence, zh)}</span>
        <span>{profile.settledCalls} calls</span>
        <span>{fmtCompact(profile.nEff)} n_eff</span>
        <span>{profile.coveredTickers} {zh ? "标的" : "tickers"}</span>
      </div>
    </Panel>
  );
}

export function SmartVoicePortfolioModule({
  symbols,
  zh,
  titleZh,
  titleEn,
  descZh,
  descEn,
}: {
  symbols: string[];
  zh: boolean;
  titleZh?: string;
  titleEn?: string;
  descZh?: string;
  descEn?: string;
}) {
  const board = useMemo(() => getPortfolioSmartVoice(symbols), [symbols]);
  return (
    <Panel className="overflow-hidden">
      <div className="flex items-start justify-between gap-3 border-b border-line px-4 py-3">
        <div>
          <div className="text-[10px] font-bold uppercase tracking-[0.16em] text-reddit">Smart Voice</div>
          <h2 className="mt-1 font-display text-[15px] font-bold leading-none text-cream">
            {zh ? titleZh || "当前持仓该听谁" : titleEn || "Best voices for your holdings"}
          </h2>
          <p className="mt-1.5 text-[12px] text-neutral-500">
            {zh
              ? descZh || "按追踪标的等权计算，后续可接入真实仓位权重。"
              : descEn || "Equal-weighted by tracked tickers; real portfolio weights can replace this later."}
          </p>
        </div>
        <div className="flex max-w-[360px] flex-wrap justify-end gap-1">
          {board.tickers.slice(0, 8).map((t) => (
            <LocaleLink key={t} href={`/tickers/${t}`} className="rounded bg-white/[.04] px-1.5 py-px font-mono text-[10.5px] text-neutral-400 hover:text-cream">
              {t}
            </LocaleLink>
          ))}
        </div>
      </div>
      <div className="grid gap-0 lg:grid-cols-5">
        {board.investors.map((inv, i) => (
          <div key={inv.id} className="border-b border-line/70 p-3 last:border-b-0 lg:border-b-0 lg:border-r lg:last:border-r-0">
            <div className="mb-2 flex items-center justify-between">
              <span className="font-mono text-[12px] font-bold text-neutral-600">#{i + 1}</span>
              <SmartVoiceScore score={inv.portfolioSv} size="sm" label="Fit SV" />
            </div>
            <InvestorIdentity inv={inv} compact />
            <div className="mt-2 space-y-1.5">
              {board.tickers.slice(0, 3).map((t) => {
                const s = investorTickerSv(inv, t).score;
                return (
                  <div key={t} className="grid grid-cols-[42px_minmax(0,1fr)_32px] items-center gap-2 text-[10.5px]">
                    <span className="font-mono text-neutral-500">{t}</span>
                    <SegmentBar value={s} />
                    <span className={`text-right font-mono tabular ${svTone(s)}`}>{s}</span>
                  </div>
                );
              })}
            </div>
          </div>
        ))}
      </div>
    </Panel>
  );
}
