"use client";

import type { Stance } from "@/shared/market/mockDetail";
import { STANCE } from "@/shared/market/kolPresentation";
import {
  LANGS,
  STANCE_FILTERS,
  SV_PRESETS,
  WINDOWS,
} from "@/features/ticker/opinionExplorerConstants";
import { shiftDay } from "@/features/ticker/opinionExplorerLogic";
import type { PersonalPrefs, SvRangeFilter } from "@/features/ticker/opinionExplorerTypes";
import { Dropdown, MenuItem, PersonalizeButton } from "./controls";

export function OpinionFilterBar({
  zh,
  fill,
  query,
  onQueryChange,
  stanceFilter,
  onStanceFilterChange,
  svFilter,
  onSvFilterChange,
  svIndexCount,
  svLowBound,
  svHighBound,
  personalConfigured,
  personalActive,
  personalDraft,
  setPersonalDraft,
  onPersonalSave,
  onPersonalClear,
  currentPrice,
  trackedAuthorsOnly,
  onTrackedAuthorsOnlyChange,
  trackingConfigured,
  maxDay,
  sinceEff,
  dateInputMinDay,
  onSinceChange,
  langs,
  availableLangs,
  onLangsChange,
  hiQ,
  onHiQChange,
  hasFilter,
  onReset,
}: {
  zh: boolean;
  fill: boolean;
  query: string;
  onQueryChange: (value: string) => void;
  stanceFilter: Set<Stance>;
  onStanceFilterChange: (value: Set<Stance>) => void;
  svFilter: SvRangeFilter;
  onSvFilterChange: (value: SvRangeFilter) => void;
  svIndexCount: number;
  svLowBound: number;
  svHighBound: number;
  personalConfigured: boolean;
  personalActive: boolean;
  personalDraft: PersonalPrefs;
  setPersonalDraft: (value: PersonalPrefs) => void;
  onPersonalSave: () => void;
  onPersonalClear: () => void;
  currentPrice?: number | null;
  trackedAuthorsOnly: boolean;
  onTrackedAuthorsOnlyChange: (value: boolean) => void;
  trackingConfigured: boolean;
  maxDay: string;
  sinceEff: string;
  dateInputMinDay: string;
  onSinceChange: (value: string) => void;
  langs: Set<string>;
  availableLangs: Set<string>;
  onLangsChange: (value: Set<string>) => void;
  hiQ: boolean;
  onHiQChange: (value: boolean) => void;
  hasFilter: boolean;
  onReset: () => void;
}) {
  const stanceLabel = (() => {
    if (stanceFilter.size === 0) return zh ? "全部" : "All";
    const labels = STANCE_FILTERS.filter((s) => stanceFilter.has(s)).map((s) => zh ? STANCE[s].zh : STANCE[s].en);
    return labels.length <= 2 ? labels.join(" / ") : (zh ? `${labels.length} 项` : `${labels.length}`);
  })();
  const svLabel = (() => {
    if (!svIndexCount) return zh ? "暂无" : "None";
    if (!svFilter.enabled) return zh ? "全部" : "All";
    const preset = SV_PRESETS.find((x) => x.key === svFilter.preset);
    if (preset && preset.key !== "off") return zh ? preset.zh : preset.en;
    return `${svLowBound}-${svHighBound}%`;
  })();
  const timeLabel = (() => {
    const w = WINDOWS.find((w) => shiftDay(maxDay, -(w.days - 1)) === sinceEff);
    return w ? (zh ? w.zh : w.en) : sinceEff || "-";
  })();
  const langLabel = langs.size === 0 ? (zh ? "全部" : "All") : (zh ? `${langs.size} 项` : String(langs.size));
  const toggleStance = (key: Stance) => {
    const next = new Set(stanceFilter);
    next.has(key) ? next.delete(key) : next.add(key);
    onStanceFilterChange(next);
  };
  const toggleLang = (key: string) => {
    const next = new Set(langs);
    next.has(key) ? next.delete(key) : next.add(key);
    onLangsChange(next);
  };

  return (
    <div className={`grid shrink-0 gap-3 px-0 py-0 lg:items-center ${fill ? "lg:grid-cols-[392px_minmax(0,1fr)]" : "lg:grid-cols-[320px_minmax(0,1fr)]"}`}>
      <label className="relative min-w-0">
        <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-neutral-600">
          <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
            <circle cx="11" cy="11" r="8" />
            <path d="m21 21-4.3-4.3" />
          </svg>
        </span>
        <input
          value={query}
          onChange={(e) => onQueryChange(e.target.value)}
          placeholder={zh ? "搜索主题、作者或正文" : "Search topic, author, or post"}
          className="h-11 w-full rounded-md bg-elevated/70 pl-9 pr-3 text-[13px] text-cream outline-none ring-1 ring-inset ring-line placeholder:text-neutral-600 focus:ring-reddit/70"
        />
      </label>
      <div className="flex min-w-0 items-center gap-2.5 overflow-x-auto">
        <Dropdown label={zh ? "情绪" : "Sentiment"} value={stanceLabel}>
          {() => (
            <div className="min-w-[150px]">
              <MenuItem active={stanceFilter.size === 0} onClick={() => onStanceFilterChange(new Set())}>
                {zh ? "全部" : "All"}
              </MenuItem>
              <div className="my-1 border-t border-line" />
              {STANCE_FILTERS.map((key) => {
                const meta = STANCE[key];
                const active = stanceFilter.has(key);
                return (
                  <MenuItem key={key} active={active} onClick={() => toggleStance(key)}>
                    <span className={`grid h-3 w-3 place-items-center rounded-full ring-1 ring-inset ${active ? "ring-[#57D7BA]" : "ring-line"}`} style={{ background: active ? meta.color : "transparent" }}>
                      {active && <span className="h-1.5 w-1.5 rounded-full bg-black/70" />}
                    </span>
                    {zh ? meta.zh : meta.en}
                  </MenuItem>
                );
              })}
            </div>
          )}
        </Dropdown>
        <Dropdown label="Score" value={svLabel}>
          {(close) => (
            <div className="w-[260px] p-1">
              <div className="px-2 pb-2 pt-1">
                <div className="flex items-center justify-between text-[11px]">
                  <span className="font-semibold text-neutral-300">{zh ? "Smart Account 排名" : "Smart Account rank"}</span>
                  <span className="font-mono text-[10.5px] text-neutral-600">{svIndexCount} {zh ? "位" : "voices"}</span>
                </div>
                <p className="mt-1 text-[10.5px] leading-snug text-neutral-600">
                  {zh ? "按当前标的的 Score 排名百分位筛选，0% 越靠近头部。" : "Filter by ticker-specific Score percentile. 0% is the top end."}
                </p>
              </div>
              {SV_PRESETS.map((preset) => (
                <MenuItem
                  key={preset.key}
                  active={svFilter.preset === preset.key}
                  disabled={!svIndexCount}
                  onClick={() => {
                    onSvFilterChange({ enabled: preset.enabled, low: preset.low, high: preset.high, preset: preset.key });
                    close();
                  }}
                >
                  <span className={`grid h-3 w-3 place-items-center rounded-[3px] ring-1 ring-inset ${svFilter.preset === preset.key ? "bg-[#57D7BA] ring-[#57D7BA]" : "ring-line"}`}>
                    {svFilter.preset === preset.key && <svg viewBox="0 0 24 24" width="9" height="9" fill="none" stroke="#0d0d0d" strokeWidth="4" strokeLinecap="round" strokeLinejoin="round" aria-hidden><path d="M5 12l5 5L20 7" /></svg>}
                  </span>
                  {zh ? preset.zh : preset.en}
                </MenuItem>
              ))}
              <div className="my-1 border-t border-line" />
              <div className="px-2 pb-1 pt-2">
                <div className="mb-2 flex items-center justify-between text-[11px]">
                  <span className="text-neutral-500">{zh ? "自定义区间" : "Custom range"}</span>
                  <span className="font-mono text-[#57D7BA]">{svLowBound}-{svHighBound}%</span>
                </div>
                <div className="space-y-2">
                  <label className="block text-[10.5px] text-neutral-600">
                    {zh ? "起点" : "From"}
                    <input
                      type="range"
                      min={0}
                      max={100}
                      step={5}
                      value={svFilter.low}
                      disabled={!svIndexCount}
                      onChange={(e) => onSvFilterChange({ ...svFilter, enabled: true, preset: "custom", low: Number(e.target.value) })}
                      className="mt-1 w-full accent-[#57D7BA]"
                    />
                  </label>
                  <label className="block text-[10.5px] text-neutral-600">
                    {zh ? "终点" : "To"}
                    <input
                      type="range"
                      min={0}
                      max={100}
                      step={5}
                      value={svFilter.high}
                      disabled={!svIndexCount}
                      onChange={(e) => onSvFilterChange({ ...svFilter, enabled: true, preset: "custom", high: Number(e.target.value) })}
                      className="mt-1 w-full accent-[#57D7BA]"
                    />
                  </label>
                </div>
              </div>
            </div>
          )}
        </Dropdown>
        <PersonalizeButton
          zh={zh}
          configured={personalConfigured}
          active={personalActive}
          draft={personalDraft}
          setDraft={setPersonalDraft}
          onSave={onPersonalSave}
          onClear={onPersonalClear}
          currentPrice={currentPrice}
        />
        <button
          type="button"
          onClick={() => onTrackedAuthorsOnlyChange(!trackedAuthorsOnly)}
          disabled={!trackingConfigured}
          className={`flex h-11 min-w-[150px] shrink-0 items-center justify-center gap-2 rounded-md px-3.5 text-[13px] font-medium ring-1 ring-inset transition ${
            trackedAuthorsOnly
              ? "bg-[#57D7BA]/12 text-[#57D7BA] ring-[#57D7BA]/70"
              : "text-neutral-400 ring-line hover:text-neutral-200"
          } disabled:cursor-not-allowed disabled:text-neutral-700 disabled:ring-line/60`}
          title={
            !trackingConfigured
              ? (zh ? "当前未配置追踪功能" : "Tracking is not configured")
              : (zh ? "只展示当前设备已追踪作者发布的观点" : "Only show opinions from authors tracked on this device")
          }
          aria-pressed={trackedAuthorsOnly}
        >
          <span className={`relative h-3.5 w-6 shrink-0 rounded-full transition ${trackedAuthorsOnly ? "bg-[#57D7BA]" : "bg-elevated"}`}>
            <span className={`absolute top-[3px] h-2 w-2 rounded-full bg-white transition-all ${trackedAuthorsOnly ? "left-[13px]" : "left-[3px]"}`} />
          </span>
          <span>{zh ? "已追踪作者" : "Tracked authors"}</span>
        </button>
        <Dropdown label={zh ? "时间" : "Time"} value={timeLabel}>
          {(close) => (
            <div className="min-w-[150px]">
              {WINDOWS.map((w) => {
                const d = shiftDay(maxDay, -(w.days - 1));
                return (
                  <MenuItem key={w.k} active={!!d && sinceEff === d} onClick={() => { onSinceChange(d); close(); }}>
                    {zh ? w.zh : w.en}
                  </MenuItem>
                );
              })}
              <div className="my-1 border-t border-line" />
              <div className="px-2 pb-1 pt-0.5">
                <span className="text-[10px] uppercase tracking-wide text-neutral-500">{zh ? "自定义起始" : "Custom from"}</span>
                <input
                  type="date"
                  value={sinceEff}
                  min={dateInputMinDay || undefined}
                  max={maxDay || undefined}
                  onChange={(e) => onSinceChange(e.target.value)}
                  className="mt-1 w-full rounded-md bg-card px-2 py-1 text-[11.5px] text-cream ring-1 ring-inset ring-line [color-scheme:dark]"
                />
              </div>
            </div>
          )}
        </Dropdown>
        <Dropdown label={zh ? "语言" : "Lang"} value={langLabel}>
          {() => (
            <div className="min-w-[140px]">
              <MenuItem active={langs.size === 0} onClick={() => onLangsChange(new Set())}>{zh ? "全部" : "All"}</MenuItem>
              <div className="my-1 border-t border-line" />
              {LANGS.map((l) => {
                const on = langs.has(l.k);
                const dim = !availableLangs.has(l.k);
                return (
                  <MenuItem key={l.k} active={on} disabled={dim} onClick={() => toggleLang(l.k)}>
                    <span className={`grid h-3 w-3 place-items-center rounded-[3px] ring-1 ring-inset ${on ? "bg-[#57D7BA] ring-[#57D7BA]" : "ring-line"}`}>
                      {on && <svg viewBox="0 0 24 24" width="9" height="9" fill="none" stroke="#0d0d0d" strokeWidth="4" strokeLinecap="round" strokeLinejoin="round" aria-hidden><path d="M5 12l5 5L20 7" /></svg>}
                    </span>
                    {zh ? l.zh : l.en}
                  </MenuItem>
                );
              })}
            </div>
          )}
        </Dropdown>
        <button
          onClick={() => onHiQChange(!hiQ)}
          className="flex h-11 min-w-[148px] shrink-0 items-center justify-center gap-2 rounded-md px-3.5 text-[13px] font-medium ring-1 ring-inset ring-line transition hover:text-neutral-200"
          title={zh ? "只展示 AI 判定为高质量(有实质分析)的帖子" : "Only AI-rated high-quality posts"}
          aria-pressed={hiQ}
        >
          <span className={`relative h-3.5 w-6 shrink-0 rounded-full transition ${hiQ ? "bg-[#57D7BA]" : "bg-elevated"}`}>
            <span className={`absolute top-[3px] h-2 w-2 rounded-full bg-white transition-all ${hiQ ? "left-[13px]" : "left-[3px]"}`} />
          </span>
          <span className={hiQ ? "text-cream" : "text-neutral-400"}>{zh ? "高质量" : "Quality"}</span>
        </button>
        <button
          type="button"
          onClick={onReset}
          disabled={!hasFilter}
          className="h-11 shrink-0 rounded-md px-3.5 text-[13px] font-semibold text-reddit transition hover:text-cream disabled:text-neutral-700"
        >
          {zh ? "清空" : "Clear All"}
        </button>
      </div>
    </div>
  );
}
