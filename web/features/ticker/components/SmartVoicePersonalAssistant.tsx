"use client";

import { useEffect, useMemo, useState } from "react";
import type { SvSignalHorizon, SvTickerSignalData } from "@/server/queries/smartVoiceTickerSignals";
import { EMPTY_PERSONAL_PREFS, STYLE_LABEL } from "../opinionExplorerConstants";
import type { PersonalDirection, PersonalPrefs, PersonalStyle } from "../opinionExplorerTypes";
import { buildPersonalDecision, buildWeightedTargetDistribution } from "../smartVoiceDecisionLogic";

const DIRECTION_OPTIONS: { value: PersonalDirection; zh: string; en: string }[] = [
  { value: "", zh: "未设", en: "Unset" },
  { value: "long", zh: "做多", en: "Long" },
  { value: "short", zh: "做空", en: "Short" },
  { value: "watch", zh: "观察", en: "Watch" },
];
const STYLE_OPTIONS: PersonalStyle[] = ["", "shortterm", "swing", "longterm", "dca"];

function NumberField({ label, value, onChange, suffix }: { label: string; value: string; onChange: (value: string) => void; suffix?: string }) {
  return (
    <label className="min-w-0">
      <span className="block text-[8px] text-neutral-600">{label}</span>
      <span className="mt-1 flex h-7 items-center rounded bg-ink/60 px-2 ring-1 ring-inset ring-line focus-within:ring-reddit/55">
        <input aria-label={label} type="number" min="0" value={value} onChange={(event) => onChange(event.target.value)} className="min-w-0 flex-1 bg-transparent font-mono text-[10px] text-cream outline-none" />
        {suffix && <span className="text-[8px] text-neutral-600">{suffix}</span>}
      </span>
    </label>
  );
}

export function SmartVoicePersonalAssistant({
  data,
  fallbackHorizon,
  zh,
}: {
  data: SvTickerSignalData;
  fallbackHorizon: SvSignalHorizon;
  zh: boolean;
}) {
  const storageKey = `prismo:opinion-personal:${data.ticker}`;
  const [prefs, setPrefs] = useState<PersonalPrefs>(EMPTY_PERSONAL_PREFS);
  const [saved, setSaved] = useState(false);
  useEffect(() => {
    try {
      const raw = window.localStorage.getItem(storageKey);
      setPrefs(raw ? { ...EMPTY_PERSONAL_PREFS, ...JSON.parse(raw) } : EMPTY_PERSONAL_PREFS);
    } catch {
      setPrefs(EMPTY_PERSONAL_PREFS);
    }
  }, [storageKey]);
  const personalHorizon = ({ shortterm: "5D", swing: "20D", longterm: "180D", dca: "180D" } as const)[prefs.style as Exclude<PersonalStyle, "">] ?? fallbackHorizon;
  const currentPrice = data.prices.at(-1)?.close ?? null;
  const targets = useMemo(
    () => buildWeightedTargetDistribution(data.evidence, personalHorizon, currentPrice, data.current[0]?.day ?? ""),
    [currentPrice, data.current, data.evidence, personalHorizon],
  );
  const decision = useMemo(
    () => buildPersonalDecision(prefs, fallbackHorizon, data.current, targets, currentPrice),
    [currentPrice, data.current, fallbackHorizon, prefs, targets],
  );
  const patch = (next: Partial<PersonalPrefs>) => { setSaved(false); setPrefs((current) => ({ ...current, ...next })); };
  const save = () => {
    try {
      const configured = Object.values(prefs).some(Boolean);
      if (configured) window.localStorage.setItem(storageKey, JSON.stringify(prefs));
      else window.localStorage.removeItem(storageKey);
      window.dispatchEvent(new CustomEvent("prismo:opinion-personal-update", { detail: { symbol: data.ticker, prefs } }));
    } catch { /* local state remains usable */ }
    setSaved(true);
  };
  const stateCopy = {
    unconfigured: zh ? "等待配置" : "Awaiting inputs",
    supportive: zh ? "信号支持仓位" : "Signals support position",
    conflicted: zh ? "信号与仓位冲突" : "Signals conflict with position",
    caution: zh ? "需要审慎验证" : "Needs validation",
  }[decision.state];
  const stateTone = decision.state === "supportive" ? "text-bull" : decision.state === "conflicted" ? "text-bear" : decision.state === "caution" ? "text-gold" : "text-neutral-500";

  return (
    <section className="border-t border-line">
      <div>
        <div className="min-w-0 border-b border-line px-4 py-3">
          <div className="flex items-center justify-between gap-3">
            <div>
              <h4 className="text-[10px] font-semibold text-neutral-300">{zh ? "个性化仓位决策助手" : "Personal position decision assistant"}</h4>
              <p className="mt-0.5 text-[8.5px] text-neutral-600">{zh ? "所有字段可选；配置会同步到上方观点推荐" : "Every field is optional; settings sync to the opinion ranking"}</p>
            </div>
            <button type="button" onClick={save} className="h-7 rounded px-3 text-[9px] font-semibold text-reddit ring-1 ring-inset ring-reddit/40 transition hover:bg-reddit/10">{saved ? (zh ? "已应用" : "Applied") : (zh ? "应用" : "Apply")}</button>
          </div>
          <div className="mt-3 grid gap-3 lg:grid-cols-2">
            <div>
              <div className="text-[8px] text-neutral-600">{zh ? "仓位方向" : "Position direction"}</div>
              <div className="mt-1 flex h-7 rounded p-0.5 ring-1 ring-inset ring-line">
                {DIRECTION_OPTIONS.map((option) => (
                  <button key={option.value || "unset"} type="button" onClick={() => patch({ direction: option.value })} className={`min-w-0 flex-1 rounded text-[9px] ${prefs.direction === option.value ? "bg-reddit/12 text-reddit ring-1 ring-inset ring-reddit/30" : "text-neutral-500"}`}>{zh ? option.zh : option.en}</button>
                ))}
              </div>
            </div>
            <div>
              <div className="text-[8px] text-neutral-600">{zh ? "操作周期" : "Trading style"}</div>
              <div className="mt-1 flex h-7 rounded p-0.5 ring-1 ring-inset ring-line">
                {STYLE_OPTIONS.map((style) => (
                  <button key={style || "unset"} type="button" onClick={() => patch({ style })} className={`min-w-0 flex-1 rounded text-[9px] ${prefs.style === style ? "bg-reddit/12 text-reddit ring-1 ring-inset ring-reddit/30" : "text-neutral-500"}`}>{style ? (zh ? STYLE_LABEL[style].zh : STYLE_LABEL[style].en) : (zh ? "未设" : "Unset")}</button>
                ))}
              </div>
            </div>
          </div>
          <div className="mt-3 grid grid-cols-2 gap-2 lg:grid-cols-3">
            <NumberField label={zh ? "成本下限" : "Cost low"} value={prefs.costLow} onChange={(value) => patch({ costLow: value })} suffix="$" />
            <NumberField label={zh ? "成本上限" : "Cost high"} value={prefs.costHigh} onChange={(value) => patch({ costHigh: value })} suffix="$" />
            <NumberField label={zh ? "仓位下限" : "Size low"} value={prefs.positionLow} onChange={(value) => patch({ positionLow: value })} suffix="%" />
            <NumberField label={zh ? "仓位上限" : "Size high"} value={prefs.positionHigh} onChange={(value) => patch({ positionHigh: value })} suffix="%" />
            <NumberField label={zh ? "个人目标" : "User target"} value={prefs.targetPrice} onChange={(value) => patch({ targetPrice: value })} suffix="$" />
            <NumberField label={zh ? "止损/失效" : "Stop / invalid."} value={prefs.stopLoss} onChange={(value) => patch({ stopLoss: value })} suffix="$" />
          </div>
        </div>
        <div className="min-w-0 px-4 py-3">
          <div className="flex items-start justify-between gap-3">
            <div>
              <div className="text-[8.5px] text-neutral-600">{zh ? `匹配周期 ${decision.horizon}` : `Matched horizon ${decision.horizon}`}</div>
              <div className={`mt-1 text-[13px] font-semibold ${stateTone}`}>{stateCopy}</div>
            </div>
            <div className="text-right">
              <div className={`font-mono text-[20px] font-bold ${stateTone}`}>{decision.score.toFixed(0)}</div>
              <div className="text-[8px] text-neutral-600">{zh ? "仓位匹配度" : "Position fit"}</div>
            </div>
          </div>
          <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-white/[.05]"><span className={`block h-full ${decision.state === "supportive" ? "bg-bull" : decision.state === "conflicted" ? "bg-bear" : "bg-gold"}`} style={{ width: `${decision.score}%` }} /></div>
          <div className="mt-2 space-y-1.5">
            {(zh ? decision.reasonsZh : decision.reasonsEn).slice(0, 4).map((reason) => <div key={reason} className="flex gap-2 text-[9px] leading-snug text-neutral-400"><span className="mt-1 h-1 w-1 shrink-0 rounded-full bg-reddit" /><span>{reason}</span></div>)}
            {decision.state === "unconfigured" && <div className="text-[9px] leading-relaxed text-neutral-600">{zh ? "填写任意字段后，系统会把真实 SV 信号、目标价和仓位风险组合成个性化判断。" : "Enter any field to combine real SV signals, targets and position risk."}</div>}
          </div>
        </div>
      </div>
    </section>
  );
}
