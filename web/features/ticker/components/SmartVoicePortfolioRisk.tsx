"use client";

import { useEffect, useMemo, useState } from "react";
import type { SvTickerLensProfile } from "@/server/queries/smartVoiceTickerSignals";
import { LENS_LABEL } from "../opinionExplorerConstants";
import { buildPortfolioRisk } from "../smartVoiceResearchLogic";

const PILOT = ["MU", "NVDA", "MSTR"] as const;

export function SmartVoicePortfolioRisk({ profiles, ticker, zh }: { profiles: SvTickerLensProfile[]; ticker: string; zh: boolean }) {
  const storageKey = "prismo:sv-pilot-portfolio";
  const [allocations, setAllocations] = useState<Record<string, string>>({ MU: "", NVDA: "", MSTR: "" });
  useEffect(() => {
    try {
      const stored = window.localStorage.getItem(storageKey);
      setAllocations(stored ? { MU: "", NVDA: "", MSTR: "", ...JSON.parse(stored) } : { MU: ticker === "MU" ? "100" : "", NVDA: ticker === "NVDA" ? "100" : "", MSTR: ticker === "MSTR" ? "100" : "" });
    } catch {
      setAllocations({ MU: ticker === "MU" ? "100" : "", NVDA: ticker === "NVDA" ? "100" : "", MSTR: ticker === "MSTR" ? "100" : "" });
    }
  }, [ticker]);
  const risk = useMemo(() => buildPortfolioRisk(profiles, Object.fromEntries(Object.entries(allocations).map(([key, value]) => [key, Number(value) || 0]))), [allocations, profiles]);
  const update = (key: string, value: string) => {
    const next = { ...allocations, [key]: value };
    setAllocations(next);
    try { window.localStorage.setItem(storageKey, JSON.stringify(next)); } catch { /* current session still works */ }
  };
  const concentrationTone = risk.concentration >= 45 ? "text-bear" : risk.concentration >= 28 ? "text-gold" : "text-bull";
  return (
    <section className="min-w-0 border-b border-line lg:border-b-0 lg:border-r">
      <div className="flex items-center justify-between gap-3 border-b border-line/70 px-4 py-2.5">
        <div>
          <h4 className="text-[10px] font-semibold text-neutral-300">{zh ? "投资组合叙事风险" : "Portfolio thesis risk"}</h4>
          <p className="mt-0.5 text-[8.5px] text-neutral-600">{zh ? "以三只试点标的真实观点视角穿透表面分散" : "Look through ticker diversification using real thesis-lens exposure"}</p>
        </div>
        <div className="text-right"><div className={`font-mono text-[15px] font-bold ${concentrationTone}`}>{risk.concentration.toFixed(0)}/100</div><div className="text-[8px] text-neutral-600">{zh ? "因子集中" : "factor concentration"}</div></div>
      </div>
      <div className="grid grid-cols-3 divide-x divide-line/60 border-b border-line/60">
        {PILOT.map((symbol) => (
          <label key={symbol} className="flex items-center gap-2 px-3 py-2">
            <span className={`text-[9px] font-semibold ${symbol === ticker ? "text-reddit" : "text-neutral-400"}`}>{symbol}</span>
            <input aria-label={`${symbol} ${zh ? "组合权重" : "portfolio weight"}`} type="number" min="0" max="100" value={allocations[symbol] ?? ""} onChange={(event) => update(symbol, event.target.value)} className="min-w-0 flex-1 bg-transparent text-right font-mono text-[10px] text-cream outline-none" />
            <span className="text-[8px] text-neutral-600">%</span>
          </label>
        ))}
      </div>
      <div className="px-4 py-3">
        <div className="space-y-2">
          {risk.exposures.slice(0, 6).map((item) => (
            <div key={item.lens} className="grid grid-cols-[72px_minmax(0,1fr)_42px] items-center gap-2">
              <span className="truncate text-[8.5px] text-neutral-400">{zh ? LENS_LABEL[item.lens]?.zh ?? item.lens : LENS_LABEL[item.lens]?.en ?? item.lens}</span>
              <span className="h-1.5 overflow-hidden rounded-full bg-white/[.05]"><span className="block h-full bg-reddit" style={{ width: `${Math.min(100, item.share * 200)}%`, opacity: 0.45 + item.share }} /></span>
              <span className="text-right font-mono text-[8.5px] text-neutral-400">{(item.share * 100).toFixed(0)}%</span>
            </div>
          ))}
        </div>
        <div className="mt-3 flex items-center justify-between border-t border-line/60 pt-2 text-[8px] text-neutral-600">
          <span>{zh ? "有效叙事因子" : "Effective thesis factors"} <b className="font-mono text-neutral-300">{risk.effectiveFactors.toFixed(1)}</b></span>
          <span>{zh ? "已配置权重" : "Configured"} <b className="font-mono text-neutral-300">{risk.configuredWeight.toFixed(0)}%</b></span>
        </div>
      </div>
    </section>
  );
}
