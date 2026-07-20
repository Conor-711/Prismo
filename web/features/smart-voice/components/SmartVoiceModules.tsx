"use client";

import { useMemo, useState } from "react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { Panel } from "@/components/ui";
import { fmtCompact } from "@/shared/formatting/format";
import {
  NARRATIVE_LABELS,
  SV_HORIZONS,
  smartVoiceBottomDecile,
  smartVoiceDecileSize,
  smartVoiceTopDecile,
  getPortfolioSmartVoice,
  investorTickerSv,
  type SvBoard,
  type SvHorizon,
  type SvInvestor,
  type SvTickerBoard,
} from "@/features/smart-voice/svMock";
import { HorizonBars, InvestorIdentity, InvestorRow, SegmentBar, SmallMetric, SmartVoiceScore, confidenceLabel, svTone } from "./SmartVoicePrimitives";

export function SmartVoiceLeaderboard({ board, expandable = false }: { board: SvBoard; expandable?: boolean }) {
  const [tab, setTab] = useState<"global" | "x" | "youtube" | "reddit" | SvHorizon | "semis" | "ai_infra">("global");
  const [band, setBand] = useState<"top" | "bottom">("top");
  const [visible, setVisible] = useState(8);
  const { lang } = useLocale();
  const zh = lang === "zh";
  const decileSize = smartVoiceDecileSize(board);
  const step = 24;
  const activePlatformBand = tab === "x" || tab === "youtube" || tab === "reddit" ? board.platformBands?.[tab] : undefined;

  const items = useMemo(() => {
    const pool = activePlatformBand
      ? (band === "bottom" ? activePlatformBand.bottom10 : activePlatformBand.top10)
      : band === "bottom"
        ? smartVoiceBottomDecile(board)
        : expandable
          ? smartVoiceTopDecile(board)
          : board.investors;
    const scored = pool.map((inv) => {
      let score = inv.sv;
      if (tab === "x" || tab === "youtube" || tab === "reddit") {
        score = inv.source === tab ? inv.platformScores[tab] ?? inv.sv : inv.sv - 14;
      } else if (band === "top") {
        if (SV_HORIZONS.includes(tab as SvHorizon)) score = inv.horizonScores[tab as SvHorizon] ?? inv.sv - 10;
        else if (tab === "semis" || tab === "ai_infra") score = inv.narrativeScores[tab] ?? inv.sv - 12;
      }
      return { inv, score };
    });
    const sorted = scored.sort((a, b) => (band === "bottom" ? a.score - b.score : b.score - a.score));
    return sorted.slice(0, expandable ? visible : 8);
  }, [activePlatformBand, band, board, expandable, tab, visible]);

  const available = activePlatformBand
    ? (band === "bottom" ? activePlatformBand.bottom10.length : activePlatformBand.top10.length)
    : band === "bottom"
      ? smartVoiceBottomDecile(board).length
      : expandable
        ? smartVoiceTopDecile(board).length
        : board.investors.length;
  const targetSize = activePlatformBand ? Math.max(1, Math.ceil(activePlatformBand.rankedCount * 0.1)) : decileSize;
  const canExpand = expandable && visible < available;

  const tabs: { key: typeof tab; zh: string; en: string }[] = [
    { key: "global", zh: "当前总分", en: "Global" },
    { key: "x", zh: "X", en: "X" },
    { key: "youtube", zh: "YouTube", en: "YouTube" },
    { key: "reddit", zh: "Reddit", en: "Reddit" },
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
            {zh ? "按最新结算后的全局分、平台分与有效样本展示。" : "Latest settled global, platform, and effective-sample scores."}
          </p>
        </div>
        <div className="grid grid-cols-3 gap-2">
          <SmallMetric label={zh ? "中位数" : "Median"} value="100" />
          <SmallMetric label={zh ? "样本池" : "Pool"} value={fmtCompact(board.totalInvestors ?? board.investors.length)} />
          <SmallMetric label={zh ? "平台" : "Platforms"} value="X/YT/RD" tone="text-reddit" />
        </div>
      </div>

      <div className="border-b border-line px-4 py-2">
        {expandable && (
          <div className="mb-2 flex flex-wrap gap-1.5">
            {(["top", "bottom"] as const).map((key) => (
              <button
                key={key}
                type="button"
                onClick={() => {
                  setBand(key);
                  setVisible(8);
                  if (key === "bottom" && tab !== "global" && tab !== "x" && tab !== "youtube" && tab !== "reddit") setTab("global");
                }}
                className={`rounded-md px-2.5 py-1 text-[11.5px] font-semibold ring-1 ring-inset transition ${
                  band === key ? "bg-white/[.07] text-cream ring-white/15" : "text-neutral-500 ring-line hover:text-cream"
                }`}
              >
                {key === "top" ? (zh ? "前 10%" : "Top 10%") : (zh ? "后 10%" : "Bottom 10%")}
              </button>
            ))}
            <span className="self-center text-[11px] text-neutral-600">
              {zh ? `目标 ${targetSize} 位 · 已导出 ${available} 位` : `target ${targetSize} · exported ${available}`}
            </span>
          </div>
        )}
        <div className="flex flex-wrap gap-1.5">
          {tabs.map((x) => (
            <button
              key={x.key}
              type="button"
              disabled={band === "bottom" && x.key !== "global" && x.key !== "x" && x.key !== "youtube" && x.key !== "reddit"}
              onClick={() => {
                setTab(x.key);
                setVisible(8);
              }}
              className={`rounded-md px-2.5 py-1 text-[11.5px] font-semibold ring-1 ring-inset transition ${
                tab === x.key ? "bg-reddit/12 text-reddit ring-reddit/35" : "text-neutral-500 ring-line hover:text-cream disabled:cursor-not-allowed disabled:opacity-35"
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
            rank={activePlatformBand && inv.platformRank ? `#${inv.platformRank}` : inv.rank ? `#${inv.rank}` : i + 1}
            zh={zh}
            suffix={<HorizonBars inv={inv} />}
          />
        ))}
      </div>

      {expandable && (
        <div className="flex items-center justify-between gap-3 border-t border-line px-4 py-2.5 text-[11px] text-neutral-500">
          <span>
            {zh
              ? `当前显示 ${items.length}/${available} 位${band === "bottom" && available < decileSize ? "；当前快照尚未完整导出后 10%" : ""}`
              : `Showing ${items.length}/${available}${band === "bottom" && available < decileSize ? "; current snapshot has not exported the full bottom 10%" : ""}`}
          </span>
          {canExpand && (
            <button
              type="button"
              onClick={() => setVisible((n) => Math.min(available, n + step))}
              className="rounded-md px-2 py-1 text-[11px] font-semibold text-reddit ring-1 ring-inset ring-reddit/25 hover:bg-reddit/10"
            >
              {visible + step >= available ? (zh ? "展开到 10%" : "Show full 10%") : (zh ? `再展开 ${Math.min(step, available - visible)} 位` : `Show ${Math.min(step, available - visible)} more`)}
            </button>
          )}
        </div>
      )}

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
