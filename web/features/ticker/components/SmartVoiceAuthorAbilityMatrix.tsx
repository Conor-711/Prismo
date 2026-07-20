"use client";

import { useMemo, useState } from "react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { smartVoiceInvestorHref } from "@/features/smart-voice";
import type { SvTickerAuthorAbility } from "@/server/queries/smartVoiceTickerSignals";

type Sort = "contribution" | "hit" | "sv";
const pct = (value: number | null) => value == null ? "—" : `${(value * 100).toFixed(0)}%`;

export function SmartVoiceAuthorAbilityMatrix({ authors, ticker, zh }: { authors: SvTickerAuthorAbility[]; ticker: string; zh: boolean }) {
  const [sort, setSort] = useState<Sort>("contribution");
  const rows = useMemo(() => [...authors].sort((a, b) => sort === "sv" ? b.sv - a.sv : sort === "hit" ? (b.weightedHitRate ?? -1) - (a.weightedHitRate ?? -1) : b.contribution - a.contribution), [authors, sort]);
  return (
    <section className="border-t border-line">
      <div className="flex items-center justify-between gap-3 border-b border-line/70 px-4 py-2.5">
        <div>
          <h4 className="text-[10px] font-semibold text-neutral-300">{zh ? `${ticker} 作者能力矩阵` : `${ticker} author ability matrix`}</h4>
          <p className="mt-0.5 text-[8.5px] text-neutral-600">{zh ? "总 SV 与该标的真实结算表现分开展示" : "Global SV and ticker-specific settled performance are shown separately"}</p>
        </div>
        <div className="flex rounded p-0.5 ring-1 ring-inset ring-line">
          {(["contribution", "hit", "sv"] as Sort[]).map((value) => <button key={value} type="button" onClick={() => setSort(value)} className={`rounded px-2 py-1 text-[8.5px] ${sort === value ? "bg-reddit/12 text-reddit" : "text-neutral-600"}`}>{value === "contribution" ? (zh ? "贡献" : "Contribution") : value === "hit" ? (zh ? "命中" : "Hit") : "SV"}</button>)}
        </div>
      </div>
      <div className="grid grid-cols-[minmax(130px,1.4fr)_48px_54px_58px_64px_70px] gap-2 border-b border-line/70 px-4 py-2 text-[8px] uppercase text-neutral-700">
        <span>{zh ? "作者" : "Author"}</span><span>SV</span><span>{zh ? "样本" : "Calls"}</span><span>{zh ? "命中" : "Hit"}</span><span>{zh ? "方向超额" : "Dir. excess"}</span><span>{zh ? "风格" : "Style"}</span>
      </div>
      <div className="max-h-[230px] divide-y divide-line/60 overflow-y-auto">
        {rows.map((author) => (
          <LocaleLink key={author.investorId} href={smartVoiceInvestorHref(author.investorId)} className="grid grid-cols-[minmax(130px,1.4fr)_48px_54px_58px_64px_70px] items-center gap-2 px-4 py-2 text-[8.5px] hover:bg-white/[.025]">
            <span className="truncate text-neutral-300">{author.name}</span>
            <span className="font-mono font-semibold text-reddit">{author.sv.toFixed(0)}</span>
            <span className="font-mono text-neutral-500">{author.tickerCalls}</span>
            <span className="font-mono text-neutral-400">{pct(author.weightedHitRate)}</span>
            <span className={`font-mono ${(author.avgDirectionalExcessPct ?? 0) >= 0 ? "text-bull" : "text-bear"}`}>{author.avgDirectionalExcessPct == null ? "—" : `${author.avgDirectionalExcessPct >= 0 ? "+" : ""}${(author.avgDirectionalExcessPct * 100).toFixed(1)}%`}</span>
            <span className="truncate text-neutral-600">{author.dominantStyle.replace("flow_momentum", "flow")}</span>
          </LocaleLink>
        ))}
      </div>
    </section>
  );
}
