"use client";

import { LENS_LABEL } from "../opinionExplorerConstants";
import type { SvThesisLifecycleItem, SvThesisState } from "../smartVoiceResearchLogic";

const STATE: Record<SvThesisState, { zh: string; en: string; tone: string }> = {
  strengthening: { zh: "增强", en: "Strengthening", tone: "text-bull" },
  fading: { zh: "衰减", en: "Fading", tone: "text-gold" },
  bullish_reversal: { zh: "转多", en: "Bull reversal", tone: "text-bull" },
  bearish_reversal: { zh: "转空", en: "Bear reversal", tone: "text-bear" },
  stable: { zh: "稳定", en: "Stable", tone: "text-neutral-400" },
  new: { zh: "新逻辑", en: "New thesis", tone: "text-reddit" },
};

function NetBar({ value }: { value: number }) {
  const width = `${Math.abs(value) * 50}%`;
  return <div className="relative h-1.5 overflow-hidden rounded-full bg-white/[.05]"><span className="absolute inset-y-0 left-1/2 w-px bg-neutral-500/60" /><span className={`absolute inset-y-0 ${value >= 0 ? "bg-bull" : "bg-bear"}`} style={{ left: value >= 0 ? "50%" : `${50 - Math.abs(value) * 50}%`, width }} /></div>;
}

export function SmartVoiceThesisLifecycle({ items, zh }: { items: SvThesisLifecycleItem[]; zh: boolean }) {
  return (
    <section className="min-w-0 border-b border-line lg:border-b-0 lg:border-r">
      <div className="border-b border-line/70 px-4 py-2.5">
        <h4 className="text-[10px] font-semibold text-neutral-300">{zh ? "投资逻辑生命周期" : "Investment thesis lifecycle"}</h4>
        <p className="mt-0.5 text-[8.5px] text-neutral-600">{zh ? "按观点视角比较最近 7 日与前 7 日的 SV 加权多空结构" : "SV-weighted thesis lenses, latest 7 days vs prior 7"}</p>
      </div>
      <div className="divide-y divide-line/60">
        {items.map((item) => {
          const copy = STATE[item.state];
          const lead = item.currentNet >= 0 ? (zh ? item.bullLeadZh : item.bullLeadEn) : (zh ? item.bearLeadZh : item.bearLeadEn);
          return (
            <div key={item.lens} className="grid grid-cols-[74px_58px_90px_minmax(0,1fr)] items-center gap-2 px-4 py-2">
              <span className="truncate text-[9px] font-semibold text-neutral-300">{zh ? LENS_LABEL[item.lens]?.zh ?? item.lens : LENS_LABEL[item.lens]?.en ?? item.lens}</span>
              <span className={`text-[8.5px] font-semibold ${copy.tone}`}>{zh ? copy.zh : copy.en}</span>
              <span className="min-w-0"><NetBar value={item.currentNet} /><span className="mt-0.5 block text-center font-mono text-[8px] text-neutral-600">{item.currentNet >= 0 ? "+" : ""}{item.currentNet.toFixed(2)}</span></span>
              <span className="line-clamp-2 text-[8.5px] leading-snug text-neutral-500" title={lead}>{lead || (zh ? "暂无结构化逻辑摘要" : "No structured thesis summary")}</span>
            </div>
          );
        })}
        {!items.length && <div className="px-4 py-8 text-center text-[10px] text-neutral-600">{zh ? "暂无视角级生命周期数据" : "No thesis lifecycle data"}</div>}
      </div>
    </section>
  );
}
