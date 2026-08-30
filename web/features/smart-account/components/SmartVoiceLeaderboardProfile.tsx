import { LocaleLink } from "@/components/i18n/LocaleLink";
import { smartVoiceInvestorHref } from "@/features/smart-account/svInvestorLinks";
import { NARRATIVE_LABELS, SV_HORIZONS } from "@/features/smart-account/svMock";
import type { SmartVoiceLeaderboardInvestor } from "@/features/smart-account/svLeaderboardData";
import {
  cleanHandle,
  formattedScore,
  HORIZON_LEVEL_LABELS,
  sourceColor,
  STYLE_LABEL,
  type HorizonLevel,
} from "@/features/smart-account/leaderboardModel";
import { Avatar } from "@/shared/market/kolPresentation";
import type { SmartVoiceRepresentativeEvidenceBundle, SmartVoiceRepresentativeShowcase } from "@/server/queries/smartVoiceInvestorQueries";
import { confidenceLabel, sourceLabel, svTone } from "./SmartVoicePrimitives";
import { SmartVoiceRepresentativeChart } from "./SmartVoiceRepresentativeChart";

export function SmartVoiceLeaderboardProfile({
  selected,
  selectedScore,
  contextualRanking,
  hasExtraFilters,
  horizonLevel,
  narrative,
  investorStyle,
  representativeShowcase,
  representativeEvidence,
  hasProfile,
  zh,
}: {
  selected: SmartVoiceLeaderboardInvestor | undefined;
  selectedScore: number | null;
  contextualRanking: boolean;
  hasExtraFilters: boolean;
  horizonLevel: HorizonLevel;
  narrative: string;
  investorStyle: string;
  representativeShowcase: SmartVoiceRepresentativeShowcase | null;
  representativeEvidence: SmartVoiceRepresentativeEvidenceBundle;
  hasProfile: boolean;
  zh: boolean;
}) {
  return (
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
              <div className="text-[9px] uppercase tracking-[0.14em] text-neutral-600">{contextualRanking ? (zh ? "能力分" : "Score") : "Score"}</div>
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

          {hasProfile ? (
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
  );
}
