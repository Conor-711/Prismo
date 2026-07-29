"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { smartVoiceInvestorHref } from "@/features/smart-voice/svInvestorLinks";
import { NARRATIVE_LABELS, SV_HORIZONS, type SvHorizon } from "@/features/smart-voice/svMock";
import type {
  SmartVoiceLeaderboardData,
  SmartVoiceLeaderboardInvestor,
} from "@/features/smart-voice/svLeaderboardData";
import { Avatar, SOURCE } from "@/shared/market/kolPresentation";
import { fmtCompact } from "@/shared/formatting/format";
import type { SmartVoiceRepresentativeEvidenceBundle } from "@/server/queries/smartVoiceInvestorQueries";
import { confidenceLabel, sourceLabel, svTone } from "./SmartVoicePrimitives";
import { SmartVoiceRepresentativeChart } from "./SmartVoiceRepresentativeChart";

type Platform = "all" | "x" | "youtube" | "reddit" | "xueqiu";
type Band = "all" | "observed" | "top" | "bottom";
type ScoreMode = "overall" | SvHorizon;
type HorizonLevel = "all" | "short" | "medium" | "long";

interface FilterOption<T extends string> {
  value: T;
  label: string;
  hint?: string;
}

const HORIZON_LEVELS: Record<Exclude<HorizonLevel, "all">, SvHorizon[]> = {
  short: ["1D", "5D"],
  medium: ["20D", "60D"],
  long: ["90D", "180D"],
};

const HORIZON_LEVEL_LABELS: Record<HorizonLevel, [string, string]> = {
  all: ["全部周期", "All horizons"],
  short: ["短线", "Short-term"],
  medium: ["中线", "Medium-term"],
  long: ["长线", "Long-term"],
};

const NARRATIVE_ORDER = [
  "semis",
  "ai_infra",
  "software",
  "consumer",
  "fintech",
  "media",
  "ev",
  "crypto",
  "other",
];

const STYLE_LABEL: Record<string, [string, string]> = {
  technical: ["技术分析", "Technical"],
  fundamental: ["基本面", "Fundamental"],
  event_driven: ["事件驱动", "Event driven"],
  macro: ["宏观", "Macro"],
  flow_momentum: ["资金流 / 动量", "Flow / momentum"],
  mixed: ["混合", "Mixed"],
  unknown: ["未分类", "Unknown"],
};

function FilterSelect<T extends string>({
  value,
  options,
  onChange,
  ariaLabel,
  active = false,
  className = "",
}: {
  value: T;
  options: FilterOption<T>[];
  onChange: (value: T) => void;
  ariaLabel: string;
  active?: boolean;
  className?: string;
}) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);
  const selected = options.find((option) => option.value === value) ?? options[0];

  useEffect(() => {
    if (!open) return;
    const close = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener("pointerdown", close);
    return () => document.removeEventListener("pointerdown", close);
  }, [open]);

  return (
    <div ref={rootRef} className={`relative ${className}`}>
      <button
        type="button"
        aria-label={ariaLabel}
        aria-haspopup="listbox"
        aria-expanded={open}
        onClick={() => setOpen((current) => !current)}
        className={`flex h-8 w-full items-center justify-between gap-2 rounded-lg px-2.5 text-[11.5px] font-medium outline-none ring-1 ring-inset transition ${
          active
            ? "bg-reddit/10 text-reddit ring-reddit/35"
            : "bg-transparent text-neutral-400 ring-line hover:text-cream hover:ring-neutral-600"
        }`}
      >
        <span className="truncate">{selected?.label}</span>
        <span aria-hidden className={`text-[10px] transition-transform ${open ? "rotate-180" : ""}`}>⌄</span>
      </button>
      {open ? (
        <div
          role="listbox"
          className="absolute left-0 top-[calc(100%+6px)] z-40 min-w-full overflow-hidden rounded-lg border border-line bg-[#181a1d] p-1 shadow-2xl shadow-black/45"
        >
          {options.map((option) => {
            const checked = option.value === value;
            return (
              <button
                key={option.value}
                type="button"
                role="option"
                aria-selected={checked}
                onClick={() => {
                  onChange(option.value);
                  setOpen(false);
                }}
                className={`flex w-full items-center justify-between gap-4 rounded-md px-2.5 py-2 text-left text-[11.5px] transition ${
                  checked ? "bg-reddit/10 text-reddit" : "text-neutral-400 hover:bg-white/[.04] hover:text-cream"
                }`}
              >
                <span className="whitespace-nowrap">{option.label}</span>
                {option.hint ? <span className="whitespace-nowrap font-mono text-[9.5px] text-neutral-600">{option.hint}</span> : null}
              </button>
            );
          })}
        </div>
      ) : null}
    </div>
  );
}

function styleLabel(inv: SmartVoiceLeaderboardInvestor, zh: boolean) {
  const key = inv.dominantInvestorType || "unknown";
  const value = STYLE_LABEL[key] ?? [key, key];
  return value[zh ? 0 : 1];
}

function scoreOf(inv: SmartVoiceLeaderboardInvestor, platform: Platform, scoreMode: ScoreMode) {
  if (scoreMode !== "overall") return inv.horizonScores[scoreMode] ?? -Infinity;
  if (platform !== "all") return inv.platformScores[platform] ?? inv.sv;
  return inv.sv;
}

function average(values: Array<number | null | undefined>) {
  const available = values.filter((value): value is number => typeof value === "number" && Number.isFinite(value));
  if (!available.length) return null;
  return available.reduce((sum, value) => sum + value, 0) / available.length;
}

function horizonLevelScore(inv: SmartVoiceLeaderboardInvestor, level: Exclude<HorizonLevel, "all">) {
  return average(HORIZON_LEVELS[level].map((horizon) => inv.horizonScores[horizon]));
}

function dominantHorizonLevel(inv: SmartVoiceLeaderboardInvestor): Exclude<HorizonLevel, "all"> | null {
  const scores = (Object.keys(HORIZON_LEVELS) as Array<Exclude<HorizonLevel, "all">>)
    .map((level) => ({ level, score: horizonLevelScore(inv, level) }))
    .filter((item): item is { level: Exclude<HorizonLevel, "all">; score: number } => item.score !== null);
  if (!scores.length) return null;
  return scores.sort((a, b) => b.score - a.score)[0].level;
}

function contextualScore(
  inv: SmartVoiceLeaderboardInvestor,
  platform: Platform,
  scoreMode: ScoreMode,
  horizonLevel: HorizonLevel,
  narrative: string,
) {
  if (scoreMode !== "overall") return scoreOf(inv, platform, scoreMode);
  const abilityScores: number[] = [];
  if (horizonLevel !== "all") {
    const value = horizonLevelScore(inv, horizonLevel);
    if (value !== null) abilityScores.push(value);
  }
  if (narrative !== "all" && typeof inv.narrativeScores[narrative] === "number") {
    abilityScores.push(inv.narrativeScores[narrative]);
  }
  return average(abilityScores) ?? scoreOf(inv, platform, scoreMode);
}

function formattedScore(value: number) {
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}

function cleanHandle(handle: string) {
  return handle.replace(/^@+/, "");
}

function sourceColor(inv: SmartVoiceLeaderboardInvestor) {
  return SOURCE[inv.source]?.color ?? "#8C96A2";
}

function uniqueInvestors(investors: SmartVoiceLeaderboardInvestor[]) {
  return [...new Map(investors.map((investor) => [investor.id, investor])).values()];
}

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
  const profileSet = useMemo(() => new Set(profileIds), [profileIds]);

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
    { value: "overall", label: zh ? "综合 SV" : "Overall SV" },
    ...SV_HORIZONS.map((horizon) => ({ value: horizon, label: `${horizon} SV` })),
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
        return band === "bottom" ? aScore - bScore : bScore - aScore;
      });
  }, [band, bandPools, horizonLevel, investorStyle, narrative, platform, query, scoreMode]);
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
    <div className="grid h-full min-h-0 lg:grid-cols-[minmax(0,1fr)_380px] xl:grid-cols-[minmax(0,1fr)_460px] 2xl:grid-cols-[minmax(0,1fr)_540px]">
      <section className="flex min-h-0 min-w-0 flex-col">
        <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-line px-3 py-2.5">
          <div className="inline-flex h-8 items-center rounded-lg bg-white/[.025] p-0.5 ring-1 ring-inset ring-line">
            {(["all", "x", "youtube", "reddit", "xueqiu"] as Platform[]).map((key) => (
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
          <label className="ml-auto flex h-8 min-w-[150px] max-w-[230px] flex-1 items-center gap-2 rounded-lg px-2.5 ring-1 ring-inset ring-line focus-within:ring-reddit/50">
            <span aria-hidden className="text-[13px] text-neutral-600">⌕</span>
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder={zh ? "搜索作者或标的" : "Search voice or ticker"}
              className="min-w-0 flex-1 bg-transparent text-[12px] text-cream outline-none placeholder:text-neutral-700"
            />
          </label>
        </div>

        <div className="grid shrink-0 grid-cols-[48px_minmax(190px,1.3fr)_110px_86px_92px_78px] items-center gap-3 border-b border-line bg-white/[.015] px-3 py-2 text-[10px] font-semibold uppercase tracking-[0.08em] text-neutral-600">
          <span>{contextualRanking ? (zh ? "筛选排名" : "Filtered rank") : (zh ? "排名" : "Rank")}</span>
          <span>{zh ? "投资者" : "Investor"}</span>
          <span>{zh ? "风格" : "Style"}</span>
          <span className="text-right">Calls</span>
          <span className="text-right">n_eff</span>
          <span className="text-right">{contextualRanking ? (zh ? "能力分" : "Score") : "SV"}</span>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto">
          {rows.map((inv, index) => {
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

      <aside className="min-h-0 overflow-y-auto border-l border-line bg-white/[.012] p-4">
        {selected ? (
          <div className="flex min-h-full flex-col">
            <div className="flex items-start gap-3">
              <Avatar src={selected.avatar} color={sourceColor(selected)} name={selected.name} size={42} />
              <div className="min-w-0 flex-1">
                <h2 className="truncate text-[15px] font-bold text-cream">{selected.name}</h2>
                <div className="mt-1 flex items-center gap-2 text-[10.5px] text-neutral-500">
                  <span style={{ color: sourceColor(selected) }}>{sourceLabel(selected.source)}</span>
                  <span>@{cleanHandle(selected.handle)}</span>
                </div>
              </div>
              <div className="text-right">
                <div className="text-[9px] uppercase tracking-[0.14em] text-neutral-600">{contextualRanking ? (zh ? "能力分" : "Score") : "SV"}</div>
                <div className={`mt-1 font-mono text-[24px] font-bold leading-none ${svTone(selectedScore ?? selected.sv)}`}>{formattedScore(selectedScore ?? selected.sv)}</div>
              </div>
            </div>

            {hasExtraFilters ? (
              <div className="mt-3 flex flex-wrap gap-1.5">
                {horizonLevel !== "all" ? <span className="rounded-md bg-reddit/10 px-2 py-1 text-[10px] font-semibold text-reddit">{HORIZON_LEVEL_LABELS[horizonLevel][zh ? 0 : 1]}</span> : null}
                {narrative !== "all" ? <span className="rounded-md bg-reddit/10 px-2 py-1 text-[10px] font-semibold text-reddit">{NARRATIVE_LABELS[narrative]?.[zh ? "zh" : "en"] ?? narrative}</span> : null}
                {investorStyle !== "all" ? <span className="rounded-md bg-reddit/10 px-2 py-1 text-[10px] font-semibold text-reddit">{STYLE_LABEL[investorStyle]?.[zh ? 0 : 1] ?? investorStyle}</span> : null}
              </div>
            ) : null}

            <p className="mt-4 border-y border-line py-3 text-[11.5px] leading-relaxed text-neutral-400">{zh ? selected.rationaleZh : selected.rationaleEn}</p>

            <dl className="grid grid-cols-2 gap-x-4 gap-y-3 py-4 text-[11px]">
              <div><dt className="text-neutral-600">{zh ? "置信度" : "Confidence"}</dt><dd className="mt-1 font-semibold text-cream">{confidenceLabel(selected.confidence, zh)}</dd></div>
              <div><dt className="text-neutral-600">{zh ? "已结算观点" : "Settled calls"}</dt><dd className="mt-1 font-mono text-[15px] font-bold text-cream">{selected.settledCalls}</dd></div>
              <div><dt className="text-neutral-600">{zh ? "活跃天数" : "Active days"}</dt><dd className="mt-1 font-mono text-[15px] font-bold text-cream">{selected.activeDays}</dd></div>
              <div><dt className="text-neutral-600">{zh ? "覆盖标的" : "Tickers"}</dt><dd className="mt-1 font-mono text-[15px] font-bold text-cream">{selected.coveredTickers}</dd></div>
            </dl>

            <div className="border-t border-line pt-3">
              <div className="text-[10px] font-semibold uppercase tracking-[0.1em] text-neutral-600">{zh ? "周期表现" : "Horizon profile"}</div>
              <div className="mt-3 space-y-2">
                {SV_HORIZONS.map((horizon) => {
                  const value = selected.horizonScores[horizon];
                  return (
                    <div key={horizon} className="grid grid-cols-[36px_minmax(0,1fr)_32px] items-center gap-2 text-[10px]">
                      <span className="font-mono text-neutral-500">{horizon}</span>
                      <span className="h-1.5 overflow-hidden rounded-full bg-white/[.05]">
                        {typeof value === "number" ? <span className="block h-full rounded-full bg-reddit" style={{ width: `${Math.max(4, Math.min(100, ((value - 70) / 100) * 100))}%` }} /> : null}
                      </span>
                      <span className={`text-right font-mono ${typeof value === "number" ? svTone(value) : "text-neutral-700"}`}>{value ?? "—"}</span>
                    </div>
                  );
                })}
              </div>
            </div>

            <div className="mt-4 flex flex-wrap gap-1.5">
              {selected.topTickers.slice(0, 6).map((ticker) => (
                <LocaleLink key={ticker} href={`/tickers/${ticker}`} className="rounded-md bg-white/[.035] px-2 py-1 font-mono text-[10.5px] text-neutral-400 ring-1 ring-inset ring-white/[.06] hover:text-reddit">{ticker}</LocaleLink>
              ))}
            </div>

            {representativeShowcase ? (
              <div className="mt-4">
                <SmartVoiceRepresentativeChart
                  showcase={representativeShowcase}
                  prices={representativeEvidence.priceByTicker[representativeShowcase.ticker] ?? []}
                  zh={zh}
                />
              </div>
            ) : null}

            {profileSet.has(selected.id) ? (
              <LocaleLink href={smartVoiceInvestorHref(selected.id)} className="mt-4 flex h-9 shrink-0 items-center justify-center rounded-lg bg-reddit text-[12px] font-bold text-[#12201d] transition hover:brightness-110">
                {zh ? "查看完整作者画像" : "Open full profile"}
              </LocaleLink>
            ) : selected.url && selected.url !== "#" ? (
              <a href={selected.url} target="_blank" rel="noopener noreferrer" className="mt-4 flex h-9 shrink-0 items-center justify-center rounded-lg text-[12px] font-bold text-reddit ring-1 ring-inset ring-reddit/35 transition hover:bg-reddit/10">
                {zh ? "查看作者主页 ↗" : "Open author ↗"}
              </a>
            ) : null}
          </div>
        ) : null}
      </aside>
    </div>
  );
}
