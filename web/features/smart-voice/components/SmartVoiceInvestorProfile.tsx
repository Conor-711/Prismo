"use client";

import { LocaleLink } from "@/components/i18n/LocaleLink";
import { Panel } from "@/components/ui";
import { fmtCompact } from "@/shared/formatting/format";
import { Avatar, SOURCE } from "@/shared/market/kolPresentation";
import {
  NARRATIVE_LABELS,
  SV_HORIZONS,
  smartVoiceDecileSize,
  type SvBoard,
  type SvInvestor,
} from "@/features/smart-voice/svMock";
import type { SmartVoiceInvestorEvidence } from "@/server/queries/smartVoiceInvestorQueries";
import {
  SegmentBar,
  SmallMetric,
  SmartVoiceScore,
  confidenceLabel,
  sourceLabel,
  svTone,
} from "./SmartVoicePrimitives";
import { SmartVoiceEvidenceChart } from "./SmartVoiceEvidenceChart";
import { SmartVoicePerformanceLedger } from "./SmartVoicePerformanceLedger";

const TYPE_LABEL: Record<string, { zh: string; en: string }> = {
  technical: { zh: "技术分析", en: "Technical" },
  fundamental: { zh: "基本面", en: "Fundamental" },
  event_driven: { zh: "事件驱动", en: "Event driven" },
  macro: { zh: "宏观", en: "Macro" },
  flow_momentum: { zh: "资金流 / 动量", en: "Flow / momentum" },
  mixed: { zh: "混合", en: "Mixed" },
  unknown: { zh: "未分类", en: "Unknown" },
};

function typeLabel(key: string | undefined, zh: boolean) {
  return TYPE_LABEL[key || "unknown"]?.[zh ? "zh" : "en"] ?? key ?? (zh ? "未分类" : "Unknown");
}

function pct(value: number | null | undefined, digits = 1) {
  if (typeof value !== "number" || Number.isNaN(value)) return "—";
  return `${(value * 100).toFixed(digits)}%`;
}

function scoreEntries(map: Record<string, number>, labels?: Record<string, { zh: string; en: string }>) {
  return Object.entries(map).sort((a, b) => b[1] - a[1]).map(([key, value]) => ({ key, value, label: labels?.[key] }));
}

function bandOf(profile: SvInvestor, board: SvBoard) {
  const platformBand = board.platformBands?.[profile.source];
  if (platformBand?.top10.some((investor) => investor.id === profile.id)) return "top";
  if (platformBand?.bottom10.some((investor) => investor.id === profile.id)) return "bottom";
  const total = board.totalInvestors ?? board.investors.length;
  const decile = smartVoiceDecileSize(board);
  const rank = profile.rank ?? 0;
  if (rank > 0 && rank <= decile) return "top";
  if (rank > 0 && rank > total - decile) return "bottom";
  return profile.sv >= 100 ? "top" : "bottom";
}

function strongestWeakest(profile: SvInvestor) {
  const scores = SV_HORIZONS
    .map((h): [string, number | null | undefined] => [h, profile.horizonScores[h]])
    .filter((entry): entry is [string, number] => typeof entry[1] === "number");
  return {
    strongest: [...scores].sort((a, b) => b[1] - a[1])[0],
    weakest: [...scores].sort((a, b) => a[1] - b[1])[0],
  };
}

function WhyList({ profile, board, zh }: { profile: SvInvestor; board: SvBoard; zh: boolean }) {
  const band = bandOf(profile, board);
  const c = profile.concentration;
  const platformScore = Number(c?.svPlatform ?? Object.values(profile.platformScores)[0] ?? profile.sv);
  const rawScore = Number(c?.svPlatformRaw ?? platformScore);
  const { strongest, weakest } = strongestWeakest(profile);
  const topNarrative = scoreEntries(profile.narrativeScores, NARRATIVE_LABELS)[0];
  const topTicker = scoreEntries(profile.tickerScores)[0];
  const points = band === "top"
    ? [
        zh ? `平台内分数 ${Math.round(platformScore)}，高于 100 基准 ${Math.round(platformScore - 100)} 分。` : `Platform score ${Math.round(platformScore)}, ${Math.round(platformScore - 100)} points above the 100 baseline.`,
        zh ? `${fmtCompact(profile.nEff)} n_eff、${profile.settledCalls} 个已结算 call，置信度为${confidenceLabel(profile.confidence, zh)}。` : `${fmtCompact(profile.nEff)} n_eff and ${profile.settledCalls} settled calls, with ${confidenceLabel(profile.confidence, zh).toLowerCase()}.`,
        strongest ? (zh ? `${strongest[0]} 时间窗口最强，得分 ${strongest[1]}。` : `Strongest on the ${strongest[0]} horizon with a ${strongest[1]} score.`) : "",
        topTicker ? (zh ? `代表标的 ${topTicker.key} 的分段 SV 为 ${topTicker.value}。` : `Representative ticker ${topTicker.key} has segment SV ${topTicker.value}.`) : "",
      ]
    : [
        zh ? `平台内分数 ${Math.round(platformScore)}，低于 100 基准 ${Math.round(100 - platformScore)} 分。` : `Platform score ${Math.round(platformScore)}, ${Math.round(100 - platformScore)} points below the 100 baseline.`,
        zh ? `${fmtCompact(profile.nEff)} n_eff、${profile.settledCalls} 个已结算 call，低分不是样本过少造成的简单噪音。` : `${fmtCompact(profile.nEff)} n_eff and ${profile.settledCalls} settled calls, so the weak score is not just thin-sample noise.`,
        weakest ? (zh ? `${weakest[0]} 时间窗口最弱，得分 ${weakest[1]}。` : `Weakest on the ${weakest[0]} horizon with a ${weakest[1]} score.`) : "",
        topNarrative ? (zh ? `主要叙事 ${topNarrative.label?.zh ?? topNarrative.key} 的分段 SV 为 ${topNarrative.value}。` : `Main narrative ${topNarrative.label?.en ?? topNarrative.key} has segment SV ${topNarrative.value}.`) : "",
      ];

  return (
    <ul className="space-y-2">
      {points.filter(Boolean).map((point) => (
        <li key={point} className="flex gap-2 text-[12.5px] leading-relaxed text-neutral-300">
          <span className={band === "top" ? "text-reddit" : "text-bear"}>●</span>
          <span>{point}</span>
        </li>
      ))}
      {c?.capApplied && (
        <li className="flex gap-2 text-[12.5px] leading-relaxed text-neutral-300">
          <span className="text-amber">●</span>
          <span>
            {zh
              ? `集中度上限已触发：原始平台分 ${Math.round(rawScore)} 被压到 ${Math.round(platformScore)}，避免单一标的贡献过大。`
              : `Concentration cap applied: raw platform score ${Math.round(rawScore)} was capped at ${Math.round(platformScore)} to avoid single-name dominance.`}
          </span>
        </li>
      )}
    </ul>
  );
}

function ExplanationModule({ profile, board, zh }: { profile: SvInvestor; board: SvBoard; zh: boolean }) {
  const platformBand = board.platformBands?.[profile.source];
  const usesPlatformRank = Boolean(platformBand && profile.platformRank);
  const total = usesPlatformRank ? platformBand?.rankedCount ?? 0 : board.totalInvestors ?? board.investors.length;
  const rank = usesPlatformRank ? profile.platformRank ?? 0 : profile.rank ?? 0;
  const percentile = rank > 0 && total > 0 ? (rank - 1) / total : null;
  const band = bandOf(profile, board);
  const activeDistribution = usesPlatformRank ? platformBand?.distribution : board.distribution;
  const threshold = band === "top" ? activeDistribution?.top10Threshold : activeDistribution?.bottom10Threshold;
  const c = profile.concentration;

  return (
    <Panel className="p-4 sm:p-5">
      <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_220px]">
        <div>
          <div className="text-[10px] font-bold uppercase tracking-[0.16em] text-reddit">SV Explanation</div>
          <h2 className="mt-1 font-display text-[18px] font-extrabold text-cream">
            {band === "top" ? (zh ? "为什么 SV 这么高" : "Why this SV is high") : (zh ? "为什么 SV 这么低" : "Why this SV is low")}
          </h2>
          <p className="mt-2 text-[12.5px] leading-relaxed text-neutral-500">{zh ? profile.rationaleZh : profile.rationaleEn}</p>
          <div className="mt-4">
            <WhyList profile={profile} board={board} zh={zh} />
          </div>
        </div>
        <div className="grid grid-cols-2 gap-2 lg:grid-cols-1">
          <SmallMetric label={usesPlatformRank ? (zh ? "平台排名" : "Platform rank") : (zh ? "全局排名" : "Global rank")} value={rank ? `#${rank}/${total}` : "—"} tone={band === "top" ? "text-reddit" : "text-bear"} />
          <SmallMetric label={zh ? "百分位" : "Percentile"} value={percentile == null ? "—" : `${(percentile * 100).toFixed(1)}%`} />
          <SmallMetric label={zh ? "10% 阈值" : "10% threshold"} value={typeof threshold === "number" ? String(threshold) : "—"} />
          <SmallMetric label={zh ? "置信折算" : "Confidence factor"} value={typeof c?.confidenceFactor === "number" ? pct(c.confidenceFactor, 0) : "—"} />
        </div>
      </div>
    </Panel>
  );
}

function StyleModule({ profile, zh }: { profile: SvInvestor; zh: boolean }) {
  const c = profile.concentration;
  const shares = Object.entries(c?.investorTypeShare ?? {}).sort((a, b) => b[1] - a[1]).slice(0, 5);
  const narratives = scoreEntries(profile.narrativeScores, NARRATIVE_LABELS).slice(0, 4);
  const tickers = scoreEntries(profile.tickerScores).slice(0, 8);
  const dominant = c?.dominantInvestorType || "unknown";

  return (
    <Panel className="p-4 sm:p-5">
      <div className="mb-4 flex items-start justify-between gap-3">
        <div>
          <div className="text-[10px] font-bold uppercase tracking-[0.16em] text-reddit">Style Fit</div>
          <h2 className="mt-1 font-display text-[17px] font-bold text-cream">{zh ? "投资风格与分类" : "Investment style and classification"}</h2>
          <p className="mt-1.5 text-[12px] text-neutral-500">
            {zh ? `主分类：${typeLabel(dominant, zh)}。用于判断他是否适合你的交易周期、标的和分析偏好。` : `Primary type: ${typeLabel(dominant, zh)}. Use this to match horizon, ticker coverage and analysis preference.`}
          </p>
        </div>
        <span className="rounded-md bg-reddit/12 px-2 py-1 text-[11px] font-bold text-reddit ring-1 ring-inset ring-reddit/25">
          {typeLabel(dominant, zh)}
        </span>
      </div>

      <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
        <div className="space-y-3">
          {shares.map(([key, value]) => (
            <div key={key}>
              <div className="mb-1 flex justify-between text-[11.5px]">
                <span className="font-semibold text-neutral-300">{typeLabel(key, zh)}</span>
                <span className="font-mono text-neutral-500">{pct(value, 0)}</span>
              </div>
              <div className="h-2 overflow-hidden rounded-full bg-white/[.05]">
                <div className="h-full rounded-full bg-reddit" style={{ width: `${Math.max(4, value * 100)}%` }} />
              </div>
            </div>
          ))}
        </div>
        <div>
          <div className="mb-2 grid grid-cols-3 gap-2">
            <SmallMetric label={zh ? "活跃天数" : "Active days"} value={String(profile.activeDays)} />
            <SmallMetric label={zh ? "覆盖标的" : "Tickers"} value={String(profile.coveredTickers)} />
            <SmallMetric label={zh ? "有效宽度" : "Eff. breadth"} value={typeof c?.effectiveTickersByWeight === "number" ? c.effectiveTickersByWeight.toFixed(1) : "—"} />
          </div>
          <div className="space-y-2">
            {SV_HORIZONS.map((h) => {
              const s = profile.horizonScores[h];
              return (
                <div key={h}>
                  <div className="mb-0.5 flex justify-between text-[10.5px] text-neutral-600">
                    <span>{h}</span>
                    <span className="font-mono">{typeof s === "number" ? s : "—"}</span>
                  </div>
                  {typeof s === "number" && <SegmentBar value={s} />}
                </div>
              );
            })}
          </div>
        </div>
      </div>

      <div className="mt-4 flex flex-wrap gap-1.5 border-t border-line/70 pt-3">
        {tickers.map(({ key, value }) => (
          <LocaleLink key={key} href={`/tickers/${key}`} className={`rounded bg-white/[.04] px-1.5 py-px font-mono text-[10.5px] hover:text-cream ${svTone(value)}`}>
            {key} {value}
          </LocaleLink>
        ))}
        {narratives.map(({ key, value, label }) => (
          <span key={key} className={`rounded bg-white/[.04] px-1.5 py-px text-[10.5px] ${svTone(value)}`}>
            {zh ? label?.zh ?? key : label?.en ?? key} {value}
          </span>
        ))}
      </div>
    </Panel>
  );
}

function EvidenceModule({ evidence, zh }: { evidence: SmartVoiceInvestorEvidence; zh: boolean }) {
  return (
    <Panel className="p-4 sm:p-5">
      <div className="mb-3 flex flex-wrap items-end justify-between gap-3">
        <div className="min-w-0 flex-1">
          <div className="text-[10px] font-bold uppercase tracking-[0.16em] text-reddit">Evidence Calls</div>
          <h2 className="mt-1 font-display text-[17px] font-bold text-cream">{zh ? "SV 贡献证据与价格路径" : "SV evidence on price action"}</h2>
          <p className="mt-1.5 text-[12px] leading-relaxed text-neutral-500">
            {zh ? "代表性已结算观点按贡献方向落在对应标的日 K 上。" : "Representative settled calls are positioned on each ticker's daily candles by score contribution."}
          </p>
        </div>
      </div>
      <SmartVoiceEvidenceChart evidence={evidence} zh={zh} />
    </Panel>
  );
}

function PerformanceModule({ evidence, zh }: { evidence: SmartVoiceInvestorEvidence; zh: boolean }) {
  return (
    <Panel className="p-4 sm:p-5">
      <div className="mb-4">
        <div className="text-[10px] font-bold uppercase tracking-[0.16em] text-reddit">Full Track Record</div>
        <h2 className="mt-1 font-display text-[17px] font-bold text-cream">{zh ? "完整已结算战绩" : "Complete settled track record"}</h2>
        <p className="mt-1.5 text-[12px] leading-relaxed text-neutral-500">
          {zh ? "覆盖该作者全部已到期观点；每条记录均按观点主周期结算，可回溯至原帖。" : "All matured calls for this investor, settled on each call's primary horizon and traceable to the source."}
        </p>
      </div>
      <SmartVoicePerformanceLedger evidence={evidence} zh={zh} />
    </Panel>
  );
}

export function SmartVoiceInvestorProfile({
  profile,
  board,
  evidence,
  zh,
}: {
  profile: SvInvestor;
  board: SvBoard;
  evidence: SmartVoiceInvestorEvidence;
  zh: boolean;
}) {
  const band = bandOf(profile, board);
  const color = SOURCE[profile.source]?.color ?? SOURCE.x.color;
  const low = band === "bottom";
  return (
    <div className="space-y-4 pb-10">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="flex min-w-0 items-start gap-4">
          <Avatar src={profile.avatar} color={color} name={profile.name} size={58} />
          <div className="min-w-0">
            <div className="mb-1 flex flex-wrap items-center gap-2">
              <h1 className="font-display text-2xl font-extrabold leading-none text-cream">{profile.name}</h1>
              <span className="rounded px-1.5 py-px text-[10px] font-medium" style={{ color, background: `${color}22` }}>
                {sourceLabel(profile.source)}
              </span>
              <span className={`rounded px-1.5 py-px text-[10px] font-bold ring-1 ring-inset ${low ? "bg-bear/10 text-bear ring-bear/25" : "bg-reddit/10 text-reddit ring-reddit/25"}`}>
                {low ? (zh ? "后 10%" : "Bottom 10%") : (zh ? "前 10%" : "Top 10%")}
              </span>
            </div>
            <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-[12px] text-neutral-500">
              <span className="font-mono">{profile.handle ? `@${profile.handle.replace(/^@/, "")}` : profile.id}</span>
              <span>{confidenceLabel(profile.confidence, zh)}</span>
              {profile.url && (
                <a href={profile.url} target="_blank" rel="noopener noreferrer" className="hover:text-cream">
                  {zh ? "平台主页 ↗" : "Source profile ↗"}
                </a>
              )}
            </div>
          </div>
        </div>
        <SmartVoiceScore score={profile.sv} size="lg" />
      </div>

      <ExplanationModule profile={profile} board={board} zh={zh} />
      <StyleModule profile={profile} zh={zh} />
      <EvidenceModule evidence={evidence} zh={zh} />
      <PerformanceModule evidence={evidence} zh={zh} />
    </div>
  );
}
