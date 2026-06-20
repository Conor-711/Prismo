"use client";

import { useState } from "react";
import { RegionBadge } from "./Bits";
import { bi, flag } from "./DetailBits";
import { regionLabel } from "@/lib/regions";
import type { Locale } from "@/lib/i18n";
import type { Bi } from "@/lib/mockDetail";

type Side = { thesis: Bi; region: string; support: number };

// 模块 6「最强反方」：用户选持仓方向（多/空），分别给出最强同向 / 反向论点（汇总文本，非原帖）。
export function CounterThesis({
  bull, bear, counterDiscussed, counterStrength, counterSources, lang,
}: {
  bull: Side; bear: Side; counterDiscussed: number; counterStrength: number; counterSources: string[]; lang: Locale;
}) {
  const zh = lang === "zh";
  const [side, setSide] = useState<"long" | "short">("long");
  const same = side === "long" ? bull : bear;
  const counter = side === "long" ? bear : bull;

  const ArgCard = ({ s, kind }: { s: Side; kind: "same" | "counter" }) => {
    const isSame = kind === "same";
    const tone = isSame ? "ring-bull/30" : "ring-bear/30";
    const head = isSame ? (zh ? "最强同向论点" : "Strongest aligned") : (zh ? "最强反向论点" : "Strongest counter");
    const dot = isSame ? "bg-bull" : "bg-bear";
    return (
      <div className={`rounded-xl bg-white/[.012] ring-1 ring-inset ${tone} p-4`}>
        <div className="flex items-center gap-2">
          <span className={`w-1.5 h-1.5 rounded-full ${dot}`} />
          <span className="text-[11px] uppercase tracking-wider text-neutral-400">{head}</span>
          <span className="ml-auto inline-flex items-center gap-1 text-[11px] text-neutral-500"><span>{flag(s.region)}</span>{regionLabel(s.region, lang)}</span>
        </div>
        <p className="mt-2 text-[14px] text-cream leading-snug">{bi(s.thesis, lang)}</p>
        <div className="mt-3">
          <div className="flex items-center justify-between text-[10px] text-neutral-500 mb-1">
            <span>{zh ? "支持度" : "Support"}</span><span className="tabular">{s.support}%</span>
          </div>
          <div className="h-1.5 w-full rounded-full bg-white/[.06] overflow-hidden">
            <div className={`h-full rounded-full ${isSame ? "bg-bull" : "bg-bear"}`} style={{ width: `${s.support}%` }} />
          </div>
        </div>
      </div>
    );
  };

  return (
    <div>
      <div className="flex flex-wrap items-center justify-between gap-3 mb-4">
        <span className="text-[12px] text-neutral-500">{zh ? "你的持仓方向" : "Your position"}</span>
        <div className="inline-flex rounded-lg ring-1 ring-inset ring-line p-0.5">
          {(["long", "short"] as const).map((s) => (
            <button
              key={s}
              onClick={() => setSide(s)}
              className={`px-3 py-1 rounded-md text-[12px] font-medium transition ${side === s ? (s === "long" ? "bg-bull/15 text-bull" : "bg-bear/15 text-bear") : "text-neutral-500 hover:text-neutral-300"}`}
            >
              {s === "long" ? (zh ? "做多" : "Long") : zh ? "做空" : "Short"}
            </button>
          ))}
        </div>
      </div>

      <div className="grid sm:grid-cols-2 gap-3">
        <ArgCard s={same} kind="same" />
        <ArgCard s={counter} kind="counter" />
      </div>

      <div className="mt-3 grid grid-cols-2 gap-3">
        <div className="rounded-lg bg-white/[.012] ring-1 ring-inset ring-line px-3 py-2.5">
          <div className="text-[10px] uppercase tracking-wider text-neutral-500">{zh ? "反方被讨论度" : "Counter discussed"}</div>
          <div className="mt-1 font-display font-bold text-cream text-[19px] tabular">{counterDiscussed}%</div>
        </div>
        <div className="rounded-lg bg-white/[.012] ring-1 ring-inset ring-line px-3 py-2.5">
          <div className="text-[10px] uppercase tracking-wider text-neutral-500">{zh ? "反方强度" : "Counter strength"}</div>
          <div className="mt-1 font-display font-bold text-cream text-[19px] tabular">{counterStrength}</div>
        </div>
      </div>

      <div className="mt-3 flex flex-wrap items-center gap-2 text-[11px] text-neutral-500">
        <span>{zh ? "反方主要来源视角：" : "Counter mainly from:"}</span>
        {counterSources.map((r) => (
          <span key={r} className="inline-flex items-center gap-1"><span>{flag(r)}</span>{regionLabel(r, lang)}</span>
        ))}
      </div>
    </div>
  );
}
