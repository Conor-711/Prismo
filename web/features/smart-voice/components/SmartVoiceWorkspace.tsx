"use client";

import { useState } from "react";
import { useLocale } from "@/components/i18n/LocaleProvider";
import type { SmartVoiceLeaderboardData } from "@/features/smart-voice/svLeaderboardData";
import { fmtCompact } from "@/shared/formatting/format";
import { ViewportWorkspace } from "@/shared/layout/ViewportWorkspace";
import type { SmartVoiceLiveCall, SmartVoiceMarketData, SmartVoiceOverviewStats } from "@/server/queries/smartVoiceQueries";
import type { SmartVoiceRepresentativeEvidenceBundle } from "@/server/queries/smartVoiceInvestorQueries";
import { SmartVoiceLeaderboardView } from "./SmartVoiceLeaderboardView";
import { SmartVoiceLiveView } from "./SmartVoiceLiveView";
import { SmartVoiceMarketView } from "./SmartVoiceMarketView";

type WorkspaceView = "market" | "leaderboard" | "live";

function latestDay(value: string, fallback: string) {
  return value ? value.slice(0, 10) : fallback;
}

export function SmartVoiceWorkspace({
  boardMeta,
  leaderboard,
  marketData,
  liveCalls,
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
  marketData: SmartVoiceMarketData;
  liveCalls: SmartVoiceLiveCall[];
  stats: SmartVoiceOverviewStats;
  profileIds: string[];
  representativeEvidence: SmartVoiceRepresentativeEvidenceBundle;
}) {
  const { lang } = useLocale();
  const zh = lang === "zh";
  const [view, setView] = useState<WorkspaceView>("market");
  const tickerBoards = marketData.boards;
  const tickerCount = new Set([
    ...tickerBoards.all["30D"].bullish.map((row) => row.ticker),
    ...tickerBoards.all["30D"].bearish.map((row) => row.ticker),
    ...tickerBoards.all["30D"].contrast.map((row) => row.ticker),
    ...tickerBoards.all["30D"].authorShift.map((row) => row.ticker),
  ]).size;
  const tabs: { key: WorkspaceView; zh: string; en: string; count: string }[] = [
    { key: "market", zh: "标的发现", en: "Top tickers", count: String(tickerCount) },
    { key: "leaderboard", zh: "投资者榜", en: "Leaderboard", count: fmtCompact(stats.scoredInvestors || boardMeta.totalInvestors) },
    { key: "live", zh: "实时观点", en: "Live calls", count: fmtCompact(liveCalls.length) },
  ];

  return (
    <ViewportWorkspace className="flex min-h-0 flex-col overflow-hidden" bottomOffset={16}>
      <header className="flex shrink-0 items-end justify-between gap-5 border-b border-line pb-2.5">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <h1 className="font-display text-[22px] font-extrabold leading-none text-cream">Smart Voice</h1>
            <span
              title={zh ? "根据作者公开观点的历史结算表现、胜率稳定性、覆盖范围与有效样本识别值得参考的声音。SV 不代表作者真实持仓。" : "Identifies valuable public voices from settled call performance, consistency, coverage and effective samples. SV does not represent actual holdings."}
              className="grid h-4 w-4 cursor-help place-items-center rounded-full text-[10px] font-bold text-neutral-500 ring-1 ring-inset ring-neutral-600"
            >i</span>
          </div>
          <p className="mt-1.5 truncate text-[11.5px] text-neutral-500">
            {zh ? "从已验证作者中发现集中关注的标的、稳定表现者与最新有效观点。" : "Discover concentrated ticker interest, consistent investors and the latest actionable public calls."}
          </p>
        </div>
        <div className="flex shrink-0 items-end divide-x divide-line text-right">
          <div className="px-3 first:pl-0">
            <div className="text-[9px] uppercase tracking-[0.1em] text-neutral-600">{zh ? "已评分作者" : "Scored voices"}</div>
            <div className="mt-1 font-mono text-[14px] font-bold leading-none text-cream">{fmtCompact(stats.scoredInvestors || boardMeta.totalInvestors)}</div>
          </div>
          <div className="px-3">
            <div className="text-[9px] uppercase tracking-[0.1em] text-neutral-600">{zh ? "高置信作者" : "High confidence"}</div>
            <div className="mt-1 font-mono text-[14px] font-bold leading-none text-reddit">{fmtCompact(stats.highConfidenceInvestors)}</div>
          </div>
          <div className="px-3">
            <div className="text-[9px] uppercase tracking-[0.1em] text-neutral-600">{zh ? "有效观点" : "Actionable calls"}</div>
            <div className="mt-1 font-mono text-[14px] font-bold leading-none text-cream">{fmtCompact(stats.actionableCalls)}</div>
          </div>
          <div className="px-3 pr-0">
            <div className="text-[9px] uppercase tracking-[0.1em] text-neutral-600">{zh ? "更新" : "Updated"}</div>
            <div className="mt-1 font-mono text-[14px] font-bold leading-none text-neutral-300">{latestDay(stats.latestCallAt, boardMeta.updatedAt)}</div>
          </div>
        </div>
      </header>

      <nav className="flex h-11 shrink-0 items-end gap-1 border-b border-line" aria-label={zh ? "Smart Voice 视图" : "Smart Voice views"}>
        {tabs.map((tab) => (
          <button
            key={tab.key}
            type="button"
            onClick={() => setView(tab.key)}
            className={`relative flex h-10 items-center gap-2 px-4 text-[12px] font-semibold outline-none transition focus-visible:ring-1 focus-visible:ring-inset focus-visible:ring-reddit/50 ${view === tab.key ? "text-cream" : "text-neutral-500 hover:text-cream"}`}
          >
            <span>{zh ? tab.zh : tab.en}</span>
            <span className={`font-mono text-[9.5px] ${view === tab.key ? "text-reddit" : "text-neutral-700"}`}>{tab.count}</span>
            {view === tab.key ? <span className="absolute inset-x-3 bottom-0 h-0.5 bg-reddit" /> : null}
          </button>
        ))}
        <div className="ml-auto pb-2.5 text-[10px] text-neutral-600">
          {zh ? `覆盖 ${stats.platformCount || 4} 个来源 · ${boardMeta.scoringVersion ?? "SV"}` : `${stats.platformCount || 4} sources · ${boardMeta.scoringVersion ?? "SV"}`}
        </div>
      </nav>

      <main className="mt-3 min-h-0 flex-1 overflow-hidden rounded-lg bg-card/55 ring-1 ring-inset ring-line">
        {view === "market" ? <SmartVoiceMarketView marketData={marketData} zh={zh} /> : null}
        {view === "leaderboard" ? (
          <SmartVoiceLeaderboardView
            leaderboard={leaderboard}
            profileIds={profileIds}
            representativeEvidence={representativeEvidence}
            zh={zh}
          />
        ) : null}
        {view === "live" ? <SmartVoiceLiveView calls={liveCalls} profileIds={profileIds} zh={zh} /> : null}
      </main>
    </ViewportWorkspace>
  );
}
