"use client";

import { useEffect, useMemo, useState } from "react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { NARRATIVE_LABELS, SV_HORIZONS } from "@/features/smart-account/svMock";
import type {
  SmartVoiceLeaderboardData,
  SmartVoiceLeaderboardInvestor,
} from "@/features/smart-account/svLeaderboardData";
import {
  cleanHandle,
  contextualScore,
  dominantHorizonLevel,
  formattedScore,
  NARRATIVE_ORDER,
  sourceColor,
  STYLE_LABEL,
  styleLabel,
  uniqueInvestors,
  type Band,
  type FilterOption,
  type HorizonLevel,
  type Platform,
  type ScoreMode,
} from "@/features/smart-account/leaderboardModel";
import { Avatar } from "@/shared/market/kolPresentation";
import { fmtCompact } from "@/shared/formatting/format";
import type { SmartVoiceRepresentativeEvidenceBundle } from "@/server/queries/smartVoiceInvestorQueries";
import { sourceLabel, svTone } from "./SmartVoicePrimitives";
import { SmartVoiceFilterSelect as FilterSelect } from "./SmartVoiceFilterSelect";
import { SmartVoiceLeaderboardProfile } from "./SmartVoiceLeaderboardProfile";

export function SmartVoiceLeaderboardView({
  leaderboard,
  profileIds,
  representativeEvidence,
  zh,
}: {
  leaderboard: SmartVoiceLeaderboardData;
  profileIds: string[];
  representativeEvidence: SmartVoiceRepresentativeEvidenceBundle;
  zh: boolean;
}) {
  const [platform, setPlatform] = useState<Platform>("all");
  const [band, setBand] = useState<Band>("all");
  const [scoreMode, setScoreMode] = useState<ScoreMode>("overall");
  const [horizonLevel, setHorizonLevel] = useState<HorizonLevel>("all");
  const [narrative, setNarrative] = useState("all");
  const [investorStyle, setInvestorStyle] = useState("all");
  const [query, setQuery] = useState("");
  const [selectedId, setSelectedId] = useState("");
  const [visibleCount, setVisibleCount] = useState(100);
  const profileSet = useMemo(() => new Set(profileIds), [profileIds]);
  const platformOptions = useMemo<Platform[]>(
    () => [
      "all",
      ...(["x", "youtube", "reddit", "xueqiu"] as const).filter((source) => {
        const sourceBand = leaderboard.bands[source];
        return Boolean(sourceBand?.rankedIds.length || sourceBand?.observedIds.length);
      }),
    ],
    [leaderboard.bands],
  );

  const bandPools = useMemo<Record<Band, SmartVoiceLeaderboardInvestor[]>>(() => {
    const resolve = (ids: string[]) => ids.flatMap((id) => {
      const investor = leaderboard.investors[id];
      return investor ? [investor] : [];
    });
    if (platform !== "all") {
      const platformBand = leaderboard.bands[platform];
      if (platformBand) {
        return {
          all: resolve(platformBand.rankedIds),
          observed: resolve(platformBand.observedIds),
          top: resolve(platformBand.top10Ids),
          bottom: resolve(platformBand.bottom10Ids),
        };
      }
      return { all: [], observed: [], top: [], bottom: [] };
    }
    const platformBands = Object.values(leaderboard.bands).filter((item) => Boolean(item));
    return {
      all: uniqueInvestors(platformBands.flatMap((item) => resolve(item?.rankedIds ?? []))),
      observed: uniqueInvestors(platformBands.flatMap((item) => resolve(item?.observedIds ?? []))),
      top: uniqueInvestors(platformBands.flatMap((item) => resolve(item?.top10Ids ?? []))),
      bottom: uniqueInvestors(platformBands.flatMap((item) => resolve(item?.bottom10Ids ?? []))),
    };
  }, [leaderboard, platform]);

  const narrativeOptions = useMemo<FilterOption<string>[]>(() => {
    const available = new Set(
      Object.values(leaderboard.investors).flatMap((investor) => Object.keys(investor.narrativeScores)),
    );
    return [
      { value: "all", label: zh ? "全部赛道" : "All sectors" },
      ...[...available]
        .sort((a, b) => {
          const aIndex = NARRATIVE_ORDER.indexOf(a);
          const bIndex = NARRATIVE_ORDER.indexOf(b);
          return (aIndex < 0 ? 99 : aIndex) - (bIndex < 0 ? 99 : bIndex) || a.localeCompare(b);
        })
        .map((key) => ({
          value: key,
          label: NARRATIVE_LABELS[key]?.[zh ? "zh" : "en"] ?? (key === "other" ? (zh ? "其他赛道" : "Other sectors") : key),
        })),
    ];
  }, [leaderboard.investors, zh]);

  const styleOptions = useMemo<FilterOption<string>[]>(() => {
    const available = new Set(
      Object.values(leaderboard.investors).map((investor) => investor.dominantInvestorType || "unknown"),
    );
    return [
      { value: "all", label: zh ? "全部风格" : "All styles" },
      ...Object.keys(STYLE_LABEL)
        .filter((key) => available.has(key))
        .map((key) => ({ value: key, label: STYLE_LABEL[key][zh ? 0 : 1] })),
    ];
  }, [leaderboard.investors, zh]);

  const horizonOptions = useMemo<FilterOption<HorizonLevel>[]>(() => [
    { value: "all", label: zh ? "全部周期" : "All horizons" },
    { value: "short", label: zh ? "擅长短线" : "Short-term strength", hint: "1D–5D" },
    { value: "medium", label: zh ? "擅长中线" : "Medium-term strength", hint: "20D–60D" },
    { value: "long", label: zh ? "擅长长线" : "Long-term strength", hint: "90D–180D" },
  ], [zh]);

  const scoreOptions = useMemo<FilterOption<ScoreMode>[]>(() => [
    { value: "overall", label: zh ? "综合 Score" : "Overall Score" },
    ...SV_HORIZONS.map((horizon) => ({ value: horizon, label: `${horizon} Score` })),
  ], [zh]);

  const rows = useMemo(() => {
    const q = query.trim().toLowerCase();
    return bandPools[band]
      .filter((inv) => !q || inv.name.toLowerCase().includes(q) || inv.handle.toLowerCase().includes(q) || inv.topTickers.some((ticker) => ticker.toLowerCase().includes(q)))
      .filter((inv) => scoreMode === "overall" || typeof inv.horizonScores[scoreMode] === "number")
      .filter((inv) => horizonLevel === "all" || dominantHorizonLevel(inv) === horizonLevel)
      .filter((inv) => narrative === "all" || typeof inv.narrativeScores[narrative] === "number")
      .filter((inv) => investorStyle === "all" || inv.dominantInvestorType === investorStyle)
      .sort((a, b) => {
        const aScore = contextualScore(a, platform, scoreMode, horizonLevel, narrative);
        const bScore = contextualScore(b, platform, scoreMode, horizonLevel, narrative);
        const scoreDelta = band === "bottom" ? aScore - bScore : bScore - aScore;
        if (scoreDelta !== 0) return scoreDelta;
        const aRank = platform === "all" ? a.rank : a.platformRank;
        const bRank = platform === "all" ? b.rank : b.platformRank;
        const rankDelta = (aRank ?? Number.MAX_SAFE_INTEGER) - (bRank ?? Number.MAX_SAFE_INTEGER);
        return band === "bottom" ? -rankDelta : rankDelta;
      });
  }, [band, bandPools, horizonLevel, investorStyle, narrative, platform, query, scoreMode]);
  const visibleRows = rows.slice(0, visibleCount);

  useEffect(() => {
    setVisibleCount(100);
  }, [band, horizonLevel, investorStyle, narrative, platform, query, scoreMode]);

  const selected = rows.find((inv) => inv.id === selectedId) ?? rows[0];
  const selectedEvidence = selected ? representativeEvidence.byInvestor[selected.id] : undefined;
  const selectedScore = selected ? contextualScore(selected, platform, scoreMode, horizonLevel, narrative) : null;
  const showWeakEvidence = band === "bottom" || (band !== "top" && selectedScore !== null ? selectedScore < 100 : false);
  const representativeShowcase = selectedEvidence
    ? (showWeakEvidence ? selectedEvidence.weak : selectedEvidence.best)
    : null;
  const contextualRanking = scoreMode !== "overall" || horizonLevel !== "all" || narrative !== "all";
  const hasExtraFilters = horizonLevel !== "all" || narrative !== "all" || investorStyle !== "all";

  return (
    <div className="grid h-full min-h-0 lg:grid-cols-[minmax(0,1fr)_360px] xl:grid-cols-[minmax(0,1fr)_400px] 2xl:grid-cols-[minmax(0,1fr)_440px]">
      <section className="flex min-h-0 min-w-0 flex-col">
        <div className="shrink-0 border-b border-line">
          <div className="flex flex-wrap items-center gap-2 px-3 py-2">
            <div className="inline-flex h-8 items-center rounded-lg bg-white/[.025] p-0.5 ring-1 ring-inset ring-line">
              {platformOptions.map((key) => (
                <button
                  key={key}
                  type="button"
                  onClick={() => {
                    setPlatform(key);
                    setSelectedId("");
                  }}
                  className={`h-7 rounded-md px-3 text-[11.5px] font-semibold transition ${platform === key ? "bg-reddit/12 text-reddit ring-1 ring-inset ring-reddit/30" : "text-neutral-500 hover:text-cream"}`}
                >
                  {key === "all" ? (zh ? "全部" : "All") : key === "youtube" ? "YouTube" : key === "reddit" ? "Reddit" : key === "xueqiu" ? (zh ? "雪球" : "Xueqiu") : "X"}
                </button>
              ))}
            </div>
            <div className="inline-flex h-8 items-center rounded-lg p-0.5 ring-1 ring-inset ring-line">
              {(["all", "observed", "top", "bottom"] as Band[]).map((key) => (
                <button
                  key={key}
                  type="button"
                  onClick={() => {
                    setBand(key);
                    setSelectedId("");
                  }}
                  className={`h-7 rounded-md px-2.5 text-[11px] font-semibold transition ${band === key ? (key === "top" ? "bg-bull/10 text-bull ring-1 ring-inset ring-bull/25" : key === "bottom" ? "bg-bear/10 text-bear ring-1 ring-inset ring-bear/25" : key === "observed" ? "bg-amber-400/10 text-amber-300 ring-1 ring-inset ring-amber-300/25" : "bg-reddit/10 text-reddit ring-1 ring-inset ring-reddit/25") : "text-neutral-500 hover:text-cream"}`}
                >
                  <span>{key === "all" ? (zh ? "正式排名" : "Qualified") : key === "observed" ? (zh ? "观察池" : "Watch pool") : key === "top" ? (zh ? "前 10%" : "Top 10%") : (zh ? "后 10%" : "Bottom 10%")}</span>
                  <span className="ml-1 font-mono text-[9.5px] opacity-65">{fmtCompact(bandPools[key].length)}</span>
                </button>
              ))}
            </div>
            <div className="ml-auto flex items-center gap-2">
              <span className="shrink-0 font-mono text-[10px] text-neutral-600">
                {fmtCompact(rows.length)} {zh ? "位作者" : "voices"}
              </span>
              <label className="flex h-8 w-[220px] items-center gap-2 rounded-lg px-2.5 ring-1 ring-inset ring-line focus-within:ring-reddit/50">
                <span aria-hidden className="text-[13px] text-neutral-600">⌕</span>
                <input
                  value={query}
                  onChange={(event) => setQuery(event.target.value)}
                  placeholder={zh ? "搜索作者或标的" : "Search voice or ticker"}
                  className="min-w-0 flex-1 bg-transparent text-[12px] text-cream outline-none placeholder:text-neutral-700"
                />
              </label>
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-2 border-t border-line/60 px-3 py-2">
            <span className="mr-1 shrink-0 text-[10px] font-semibold uppercase tracking-[0.08em] text-neutral-600">
              {zh ? "能力筛选" : "Expertise"}
            </span>
            <FilterSelect
              value={scoreMode}
              options={scoreOptions}
              onChange={(value) => {
                setScoreMode(value);
                setSelectedId("");
              }}
              ariaLabel={zh ? "选择排序分数" : "Select ranking score"}
              active={scoreMode !== "overall"}
              className="w-[104px]"
            />
            <FilterSelect
              value={horizonLevel}
              options={horizonOptions}
              onChange={(value) => {
                setHorizonLevel(value);
                setSelectedId("");
              }}
              ariaLabel={zh ? "筛选优势周期" : "Filter horizon strength"}
              active={horizonLevel !== "all"}
              className="w-[112px]"
            />
            <FilterSelect
              value={narrative}
              options={narrativeOptions}
              onChange={(value) => {
                setNarrative(value);
                setSelectedId("");
              }}
              ariaLabel={zh ? "筛选擅长赛道" : "Filter sector expertise"}
              active={narrative !== "all"}
              className="w-[118px]"
            />
            <FilterSelect
              value={investorStyle}
              options={styleOptions}
              onChange={(value) => {
                setInvestorStyle(value);
                setSelectedId("");
              }}
              ariaLabel={zh ? "筛选投资风格" : "Filter investment style"}
              active={investorStyle !== "all"}
              className="w-[118px]"
            />
            {hasExtraFilters ? (
              <button
                type="button"
                onClick={() => {
                  setHorizonLevel("all");
                  setNarrative("all");
                  setInvestorStyle("all");
                  setSelectedId("");
                }}
                className="h-8 px-1.5 text-[11px] font-semibold text-reddit transition hover:text-cream"
              >
                {zh ? "清除筛选" : "Clear"}
              </button>
            ) : null}
          </div>
        </div>

        <div className="grid shrink-0 grid-cols-[48px_minmax(190px,1.3fr)_110px_86px_92px_78px] items-center gap-3 border-b border-line bg-white/[.015] px-3 py-2 text-[10px] font-semibold uppercase tracking-[0.08em] text-neutral-600">
          <span>{contextualRanking ? (zh ? "筛选排名" : "Filtered rank") : (zh ? "排名" : "Rank")}</span>
          <span>{zh ? "投资者" : "Investor"}</span>
          <span>{zh ? "风格" : "Style"}</span>
          <span className="text-right">Calls</span>
          <span className="text-right">n_eff</span>
          <span className="text-right">{contextualRanking ? (zh ? "能力分" : "Score") : "Score"}</span>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto">
          {visibleRows.map((inv, index) => {
            const displayScore = contextualScore(inv, platform, scoreMode, horizonLevel, narrative);
            const rank = contextualRanking ? index + 1 : band === "observed" && inv.observationRank
              ? inv.observationRank
              : platform !== "all" && inv.platformRank ? inv.platformRank : inv.rank ?? index + 1;
            const active = selected?.id === inv.id;
            return (
              <button
                key={inv.id}
                type="button"
                onClick={() => setSelectedId(inv.id)}
                className={`grid w-full grid-cols-[48px_minmax(190px,1.3fr)_110px_86px_92px_78px] items-center gap-3 border-b border-line/70 px-3 py-2 text-left transition ${active ? "bg-reddit/[.055] shadow-[inset_2px_0_0_#57D7BA]" : "hover:bg-white/[.025]"}`}
              >
                <span className="font-mono text-[11px] text-neutral-600">#{rank}</span>
                <span className="flex min-w-0 items-center gap-2.5">
                  <Avatar src={inv.avatar} color={sourceColor(inv)} name={inv.name} size={30} />
                  <span className="min-w-0">
                    <span className="block truncate text-[12.5px] font-semibold text-cream">{inv.name}</span>
                    <span className="mt-0.5 flex items-center gap-1.5 text-[10px] text-neutral-600">
                      <span style={{ color: sourceColor(inv) }}>{sourceLabel(inv.source)}</span>
                      <span>·</span>
                      <span>@{cleanHandle(inv.handle)}</span>
                    </span>
                  </span>
                </span>
                <span className="truncate text-[11px] text-neutral-500">{styleLabel(inv, zh)}</span>
                <span className="text-right font-mono text-[11.5px] text-neutral-300">{inv.settledCalls}</span>
                <span className="text-right font-mono text-[11.5px] text-neutral-300">{fmtCompact(inv.nEff)}</span>
                <span className={`text-right font-mono text-[15px] font-bold ${svTone(displayScore)}`}>{formattedScore(displayScore)}</span>
              </button>
            );
          })}
          {visibleRows.length < rows.length ? (
            <button
              type="button"
              onClick={() => setVisibleCount((current) => Math.min(rows.length, current + 100))}
              className="flex h-10 w-full items-center justify-center border-b border-line text-[11px] font-semibold text-reddit transition hover:bg-reddit/[.04] hover:text-cream"
            >
              {zh
                ? `加载更多 · 还剩 ${fmtCompact(rows.length - visibleRows.length)} 位`
                : `Load more · ${fmtCompact(rows.length - visibleRows.length)} remaining`}
            </button>
          ) : null}
          {!rows.length ? (
            <div className="grid h-full place-items-center px-6 text-center">
              <div>
                <div className="text-[12px] text-neutral-500">{zh ? "没有同时满足这些条件的作者" : "No investors match all selected filters"}</div>
                {hasExtraFilters ? (
                  <button
                    type="button"
                    onClick={() => {
                      setHorizonLevel("all");
                      setNarrative("all");
                      setInvestorStyle("all");
                    }}
                    className="mt-3 text-[11px] font-semibold text-reddit hover:text-cream"
                  >
                    {zh ? "清除能力筛选" : "Clear expertise filters"}
                  </button>
                ) : null}
              </div>
            </div>
          ) : null}
        </div>
      </section>

      <SmartVoiceLeaderboardProfile
        selected={selected}
        selectedScore={selectedScore}
        contextualRanking={contextualRanking}
        hasExtraFilters={hasExtraFilters}
        horizonLevel={horizonLevel}
        narrative={narrative}
        investorStyle={investorStyle}
        representativeShowcase={representativeShowcase}
        representativeEvidence={representativeEvidence}
        hasProfile={Boolean(selected && profileSet.has(selected.id))}
        zh={zh}
      />
    </div>
  );
}
