import { sentTextClass } from "@/lib/format";
import { regionColor, regionLabel } from "@/lib/regions";
import type { Locale } from "@/lib/i18n";

// 纯展示组件（无 hook）：服务端/客户端页面均可用。Prismo 各页共享。

export function Kpi({ label, value, sub }: { label: string; value: string | number; sub?: string }) {
  return (
    <div className="rounded-xl bg-card ring-1 ring-inset ring-line px-4 py-3.5">
      <div className="text-[11px] uppercase tracking-wider text-neutral-500">{label}</div>
      <div className="mt-1 font-display font-extrabold text-cream text-[26px] leading-none tabular">{value}</div>
      {sub && <div className="mt-1 text-[11px] text-neutral-600">{sub}</div>}
    </div>
  );
}

// 情绪分（-1..1）→ 带符号 + 绿/红/中性着色 + 等宽。
export function SentScore({ score, className = "" }: { score: number; className?: string }) {
  const s = Number(score) || 0;
  return (
    <span className={`font-mono font-semibold tabular ${sentTextClass(s)} ${className}`}>
      {s > 0 ? "+" : ""}
      {s.toFixed(2)}
    </span>
  );
}

const CONSENSUS: Record<string, { zh: string; en: string; cls: string }> = {
  all_bull: { zh: "共同看多", en: "Agree bullish", cls: "bg-bull/15 text-bull ring-bull/30" },
  all_bear: { zh: "共同看空", en: "Agree bearish", cls: "bg-bear/15 text-bear ring-bear/30" },
  divergent: { zh: "地区分歧", en: "Divergent", cls: "bg-reddit/15 text-reddit ring-reddit/30" },
  mixed: { zh: "分歧", en: "Mixed", cls: "bg-white/[.06] text-neutral-300 ring-white/10" },
  sparse: { zh: "数据少", en: "Sparse", cls: "bg-white/[.04] text-neutral-500 ring-white/10" },
};
export function Consensus({ value, lang }: { value: string; lang: Locale }) {
  const c = CONSENSUS[value] ?? CONSENSUS.mixed;
  return (
    <span className={`inline-flex items-center rounded-full px-2 py-0.5 text-[11px] font-semibold ring-1 ring-inset ${c.cls}`}>
      {lang === "zh" ? c.zh : c.en}
    </span>
  );
}

export function RegionBadge({ region, lang, className = "" }: { region: string; lang: Locale; className?: string }) {
  return (
    <span className={`inline-flex items-center gap-1.5 text-[12px] text-neutral-300 ${className}`}>
      <span className="w-2 h-2 rounded-full shrink-0" style={{ background: regionColor(region) }} />
      {regionLabel(region, lang)}
    </span>
  );
}

// 多空占比迷你条（按三者之和归一化：bull 绿 / neutral 灰 / bear 红）。
export function StanceBar({ bull, bear, neutral, className = "" }: { bull: number; bear: number; neutral: number; className?: string }) {
  const tot = Math.max(1e-9, bull + bear + neutral);
  const b = (bull / tot) * 100,
    n = (neutral / tot) * 100,
    r = (bear / tot) * 100;
  return (
    <div className={`flex h-1.5 w-full overflow-hidden rounded-full bg-white/[.05] ${className}`}>
      <span style={{ width: `${b}%`, background: "#57D7BA" }} />
      <span style={{ width: `${n}%`, background: "#7A8A96" }} />
      <span style={{ width: `${r}%`, background: "#fe5555" }} />
    </div>
  );
}
