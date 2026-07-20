"use client";

import type { SvExplainableAlert } from "../smartVoiceResearchLogic";

const TONE: Record<SvExplainableAlert["severity"], { dot: string; text: string; labelZh: string; labelEn: string }> = {
  high: { dot: "bg-bear", text: "text-bear", labelZh: "高", labelEn: "High" },
  medium: { dot: "bg-gold", text: "text-gold", labelZh: "中", labelEn: "Medium" },
  info: { dot: "bg-reddit", text: "text-reddit", labelZh: "信息", labelEn: "Info" },
};

export function SmartVoiceAlertCenter({ alerts, zh }: { alerts: SvExplainableAlert[]; zh: boolean }) {
  return (
    <section className="min-w-0">
      <div className="flex items-center justify-between gap-3 border-b border-line/70 px-4 py-2.5">
        <div>
          <h4 className="text-[10px] font-semibold text-neutral-300">{zh ? "可解释智能提醒" : "Explainable smart alerts"}</h4>
          <p className="mt-0.5 text-[8.5px] text-neutral-600">{zh ? "只由可追溯阈值触发，不使用黑箱买卖结论" : "Triggered by traceable thresholds, not black-box trade advice"}</p>
        </div>
        <span className="rounded bg-white/[.04] px-1.5 py-0.5 font-mono text-[8px] text-neutral-500">{alerts.length}</span>
      </div>
      <div className="divide-y divide-line/60">
        {alerts.map((alert) => {
          const tone = TONE[alert.severity];
          return (
            <div key={alert.id} className="flex gap-2.5 px-4 py-2.5">
              <span className={`mt-1 h-2 w-2 shrink-0 rounded-full ${tone.dot}`} />
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2"><span className={`text-[9.5px] font-semibold ${tone.text}`}>{zh ? alert.titleZh : alert.titleEn}</span><span className="text-[7.5px] uppercase text-neutral-700">{zh ? tone.labelZh : tone.labelEn}</span></div>
                <p className="mt-1 text-[8.5px] leading-relaxed text-neutral-500">{zh ? alert.reasonZh : alert.reasonEn}</p>
              </div>
            </div>
          );
        })}
      </div>
    </section>
  );
}
