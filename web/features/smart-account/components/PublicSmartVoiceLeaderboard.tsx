"use client";

import { useMemo } from "react";
import { useLocale } from "@/components/i18n/LocaleProvider";
import type { SmartVoiceLeaderboardData } from "@/features/smart-account/svLeaderboardData";
import { fmtCompact } from "@/shared/formatting/format";
import type { SmartVoiceOverviewStats } from "@/server/queries/smartVoiceQueries";
import type { SmartVoiceRepresentativeEvidenceBundle } from "@/server/queries/smartVoiceInvestorQueries";
import { SmartVoiceLeaderboardView } from "./SmartVoiceLeaderboardView";

function latestDay(value: string, fallback: string) {
  return (value || fallback).slice(0, 10);
}

function PublicMetric({
  label,
  value,
  accent = false,
}: {
  label: string;
  value: string;
  accent?: boolean;
}) {
  return (
    <div className="min-w-[104px] border-l border-line pl-4 first:border-l-0 first:pl-0">
      <div className="text-[9px] font-semibold uppercase tracking-[0.1em] text-neutral-600">{label}</div>
      <div className={`mt-1 font-mono text-[17px] font-bold leading-none ${accent ? "text-reddit" : "text-cream"}`}>{value}</div>
    </div>
  );
}

export function PublicSmartVoiceLeaderboard({
  boardMeta,
  leaderboard,
  stats,
  profileIds,
  representativeEvidence,
}: {
  boardMeta: {
    totalInvestors: number;
    updatedAt: string;
    scoringVersion?: string;
  };
  leaderboard: SmartVoiceLeaderboardData;
  stats: SmartVoiceOverviewStats;
  profileIds: string[];
  representativeEvidence: SmartVoiceRepresentativeEvidenceBundle;
}) {
  const { lang } = useLocale();
  const zh = lang === "zh";
  const qualifiedCount = useMemo(
    () => new Set(Object.values(leaderboard.bands).flatMap((band) => band?.rankedIds ?? [])).size,
    [leaderboard.bands],
  );
  const sourceCount = useMemo(
    () => Object.values(leaderboard.bands).filter((band) => Boolean(band?.rankedIds.length)).length,
    [leaderboard.bands],
  );

  return (
    <div className="mx-auto flex h-[calc(100dvh-3.5rem)] min-h-0 w-full max-w-[1800px] flex-col overflow-hidden px-4 py-3 sm:px-6 xl:px-8">
      <section className="flex shrink-0 items-end justify-between gap-8 border-b border-line pb-3">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <h1 className="font-display text-[23px] font-extrabold leading-none text-cream">
              {zh ? "Smart Account 投资者榜" : "Smart Account Investor Ranking"}
            </h1>
            <span className="rounded-sm bg-reddit/10 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-[0.1em] text-reddit ring-1 ring-inset ring-reddit/25">
              Public
            </span>
            <span
              title={zh ? "Score 根据作者公开观点的历史结算表现、稳定性、覆盖范围与有效样本计算，不代表作者真实持仓。" : "Score is calculated from settled public calls, consistency, coverage and effective samples. It does not represent actual holdings."}
              className="grid h-4 w-4 cursor-help place-items-center rounded-full text-[10px] font-bold text-neutral-500 ring-1 ring-inset ring-neutral-600"
            >
              i
            </span>
          </div>
          <p className="mt-1.5 max-w-[760px] truncate text-[11.5px] text-neutral-500">
            {zh
              ? "按平台、周期、赛道与投资风格比较公开观点的历史有效性，并查看每位作者的代表性证据。"
              : "Compare the historical effectiveness of public calls by platform, horizon, sector and investment style."}
          </p>
        </div>

        <div className="flex shrink-0 items-end gap-5 text-right">
          <PublicMetric label={zh ? "正式排名" : "Qualified"} value={fmtCompact(qualifiedCount || stats.scoredInvestors || boardMeta.totalInvestors)} />
          <PublicMetric label={zh ? "高置信作者" : "High confidence"} value={fmtCompact(stats.highConfidenceInvestors)} accent />
          <PublicMetric label={zh ? "有效观点" : "Actionable calls"} value={fmtCompact(stats.actionableCalls)} />
          <PublicMetric label={zh ? "榜单来源" : "Ranking sources"} value={String(sourceCount)} />
          <PublicMetric label={zh ? "更新日期" : "Updated"} value={latestDay(stats.latestCallAt, boardMeta.updatedAt)} />
        </div>
      </section>

      <div id="methodology" className="flex h-9 shrink-0 items-center gap-3 overflow-x-auto border-b border-line text-[10.5px] text-neutral-500">
        <span className="font-semibold text-neutral-300">{zh ? "评分框架" : "Scoring framework"}</span>
        <span className="h-3 w-px bg-line" />
        <span>{zh ? "历史观点逐日结算" : "Daily settled calls"}</span>
        <span className="text-neutral-700">·</span>
        <span>{zh ? "SPY 与行业 ETF 双基准" : "SPY + sector ETF benchmarks"}</span>
        <span className="text-neutral-700">·</span>
        <span>{zh ? "有效样本与时间衰减" : "Effective samples + time decay"}</span>
        <span className="text-neutral-700">·</span>
        <span>{zh ? `版本 ${boardMeta.scoringVersion ?? "Score"}` : `Version ${boardMeta.scoringVersion ?? "Score"}`}</span>
        <span className="ml-auto shrink-0 text-neutral-700">{zh ? "仅供研究，不构成投资建议" : "Research only, not investment advice"}</span>
      </div>

      <section className="mt-3 min-h-0 flex-1 overflow-hidden rounded-md bg-card/55 ring-1 ring-inset ring-line">
        <SmartVoiceLeaderboardView
          leaderboard={leaderboard}
          profileIds={profileIds}
          representativeEvidence={representativeEvidence}
          zh={zh}
        />
      </section>
    </div>
  );
}
