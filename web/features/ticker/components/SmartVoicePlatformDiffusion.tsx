"use client";

import type { SvPlatformDiffusionItem } from "../smartVoiceResearchLogic";

const SOURCE_LABEL: Record<string, string> = { x: "X", youtube: "YouTube", reddit: "Reddit", xueqiu: "雪球", toss: "Toss" };
const SOURCE_COLOR: Record<string, string> = { x: "#A7A9AC", youtube: "#FF5C6C", reddit: "#FF8B60", xueqiu: "#55B9E8", toss: "#57D7BA" };

export function SmartVoicePlatformDiffusion({ items, zh }: { items: SvPlatformDiffusionItem[]; zh: boolean }) {
  return (
    <section className="min-w-0">
      <div className="border-b border-line/70 px-4 py-2.5">
        <h4 className="text-[10px] font-semibold text-neutral-300">{zh ? "跨平台信息扩散" : "Cross-platform information diffusion"}</h4>
        <p className="mt-0.5 text-[8.5px] text-neutral-600">{zh ? "当前周期内各平台首次出现、峰值日期、声音份额与方向" : "First appearance, peak day, voice share and direction by platform"}</p>
      </div>
      <div className="px-4 py-3">
        <div className="relative ml-[78px] mr-2 h-px bg-line"><span className="absolute -top-1 left-0 h-2 w-px bg-neutral-500" /><span className="absolute -top-1 right-0 h-2 w-px bg-neutral-500" /></div>
        <div className="mt-2 space-y-3">
          {items.map((item) => (
            <div key={item.source} className="grid grid-cols-[70px_minmax(0,1fr)_58px] items-center gap-2">
              <div>
                <div className="text-[9px] font-semibold" style={{ color: SOURCE_COLOR[item.source] ?? "#A7A9AC" }}>{SOURCE_LABEL[item.source] ?? item.source}</div>
                <div className="text-[7.5px] text-neutral-700">{item.calls} call · {item.authors} {zh ? "人" : "voices"}</div>
              </div>
              <div className="relative h-5 rounded bg-white/[.025]">
                <span className="absolute inset-y-1 rounded" style={{ left: `${Math.min(88, item.leadDays * 2.4)}%`, width: `${Math.max(5, item.weightedShare * 80)}%`, backgroundColor: SOURCE_COLOR[item.source] ?? "#A7A9AC", opacity: 0.58 }} />
                <span className="absolute top-1/2 h-2 w-2 -translate-y-1/2 rounded-full ring-2 ring-ink" style={{ left: `${Math.min(96, item.leadDays * 2.4 + item.weightedShare * 40)}%`, backgroundColor: SOURCE_COLOR[item.source] ?? "#A7A9AC" }} title={`${zh ? "峰值" : "Peak"} ${item.peakDay}`} />
              </div>
              <div className="text-right">
                <div className={`font-mono text-[9px] ${item.weightedNet >= 0 ? "text-bull" : "text-bear"}`}>{item.weightedNet >= 0 ? "+" : ""}{item.weightedNet.toFixed(2)}</div>
                <div className="text-[7.5px] text-neutral-700">+{item.leadDays}d · {(item.weightedShare * 100).toFixed(0)}%</div>
              </div>
            </div>
          ))}
          {!items.length && <div className="py-8 text-center text-[10px] text-neutral-600">{zh ? "该周期暂无跨平台证据" : "No cross-platform evidence for this horizon"}</div>}
        </div>
        {!!items.length && <div className="mt-3 flex justify-between border-t border-line/60 pt-2 text-[8px] text-neutral-700"><span>{items[0]?.firstDay}</span><span>{zh ? "圆点为平台讨论峰值" : "Dot marks platform peak"}</span><span>{items.map((item) => item.latestDay).sort().at(-1)}</span></div>}
      </div>
    </section>
  );
}
