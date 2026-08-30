"use client";

import { LocaleLink } from "@/components/i18n/LocaleLink";
import { fmtCompact } from "@/shared/formatting/format";
import { Avatar, SOURCE } from "@/shared/market/kolPresentation";
import { smartVoiceInvestorHref } from "@/features/smart-account/svInvestorLinks";
import { SV_HORIZONS, type SvConfidence, type SvHorizon, type SvInvestor } from "@/features/smart-account/svMock";

export function confidenceLabel(c: SvConfidence, zh: boolean) {
  if (c === "high") return zh ? "高置信" : "High confidence";
  if (c === "medium") return zh ? "中置信" : "Medium confidence";
  if (c === "low") return zh ? "低置信" : "Low confidence";
  return zh ? "观察中" : "Observing";
}

export function svTone(score: number) {
  if (score >= 120) return "text-bull";
  if (score >= 105) return "text-cream";
  if (score >= 95) return "text-neutral-400";
  return "text-bear";
}

export function sourceLabel(source: SvInvestor["source"]) {
  if (source === "youtube") return "YouTube";
  if (source === "reddit") return "Reddit";
  if (source === "xueqiu") return "雪球";
  if (source === "toss") return "Toss";
  return "X";
}

export function SmartVoiceScore({
  score,
  label = "Score",
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

export function SegmentBar({ value, max = 145 }: { value: number; max?: number }) {
  const width = Math.max(4, Math.min(100, ((value - 80) / (max - 80)) * 100));
  return (
    <div className="h-1.5 overflow-hidden rounded-full bg-white/[.06]">
      <div className="h-full rounded-full bg-reddit" style={{ width: `${width}%` }} />
    </div>
  );
}

export function InvestorIdentity({
  inv,
  compact = false,
  link = "detail",
}: {
  inv: SvInvestor;
  compact?: boolean;
  link?: "detail" | "external" | "none";
}) {
  const color = SOURCE[inv.source]?.color ?? SOURCE.x.color;
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

  const className = "flex min-w-0 items-center gap-2.5 transition hover:opacity-85";
  if (link === "detail") {
    return (
      <LocaleLink href={smartVoiceInvestorHref(inv.id)} className={className}>
        {content}
      </LocaleLink>
    );
  }
  if (link === "external" && inv.url) {
    return (
      <a href={inv.url} target="_blank" rel="noopener noreferrer" className={className}>
        {content}
      </a>
    );
  }
  return <div className={className}>{content}</div>;
}

export function InvestorRow({
  inv,
  rank,
  zh,
  score,
  suffix,
  link = "detail",
}: {
  inv: SvInvestor;
  rank: number | string;
  zh: boolean;
  score?: number;
  suffix?: React.ReactNode;
  link?: "detail" | "external" | "none";
}) {
  const displayScore = score ?? inv.sv;
  const rationale = zh ? inv.rationaleZh : inv.rationaleEn;
  return (
    <div className="grid grid-cols-[34px_minmax(0,1fr)_auto] items-center gap-3 border-b border-line/70 px-3 py-2.5 last:border-b-0">
      <div className="text-center font-mono text-[12px] font-bold tabular text-neutral-600">{rank}</div>
      <div className="min-w-0">
        <InvestorIdentity inv={inv} link={link} />
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

export function SmallMetric({ label, value, tone = "text-cream" }: { label: string; value: string; tone?: string }) {
  return (
    <div className="rounded-lg bg-white/[.025] px-2.5 py-2 ring-1 ring-inset ring-white/[.06]">
      <div className="text-[9.5px] uppercase tracking-wide text-neutral-600">{label}</div>
      <div className={`mt-0.5 font-mono text-[13px] font-bold leading-none tabular ${tone}`}>{value}</div>
    </div>
  );
}

export function HorizonBars({ inv }: { inv: SvInvestor }) {
  return (
    <div className="mt-1.5 grid grid-cols-4 gap-1.5">
      {SV_HORIZONS.map((h: SvHorizon) => (
        <div key={h}>
          <div className="mb-0.5 flex justify-between text-[9.5px] text-neutral-600">
            <span>{h}</span>
            <span className="font-mono">{inv.horizonScores[h] ?? "—"}</span>
          </div>
          {typeof inv.horizonScores[h] === "number" && <SegmentBar value={inv.horizonScores[h] as number} />}
        </div>
      ))}
    </div>
  );
}

export function EvidencePill({ label, value }: { label: string; value: string | number }) {
  return (
    <span className="rounded bg-white/[.04] px-1.5 py-px text-[10.5px] text-neutral-500">
      {label} <b className="font-mono text-neutral-300">{typeof value === "number" ? fmtCompact(value) : value}</b>
    </span>
  );
}
