import { RegionBadge } from "./Bits";
import { regionLabel, regionColor } from "@/lib/regions";
import { sentTextClass } from "@/lib/format";
import { IconFlame, IconLayers, IconTrend, IconPulse, IconDoc } from "@/components/icons";
import type { Locale } from "@/lib/i18n";
import type { Bi } from "@/lib/mockDetail";

// 详情页模块的纯展示件（server-safe，无 hook / 无图表）。

export const bi = (t: Bi, lang: Locale) => (lang === "zh" ? t.zh : t.en);

const FLAG: Record<string, string> = { us: "🇺🇸", cn: "🇨🇳", jp: "🇯🇵", kr: "🇰🇷", tw: "🇹🇼" };
export const flag = (r: string) => FLAG[r] ?? "🏳️";

// 模块外壳：一个面板 = 一个模块（图标+标题+副标在内部表头，下接单一内容区）。
// 仿 QuiverQuant —— 少量大面板、内部留白/发丝线分隔，避免「卡中卡」的盒子堆叠。
const MICON: Record<string, (p: { className?: string }) => JSX.Element> = { flame: IconFlame, layers: IconLayers, trend: IconTrend, pulse: IconPulse, doc: IconDoc };
const MACCENT: Record<string, string> = {
  reddit: "bg-reddit/12 text-reddit ring-reddit/25",
  amber: "bg-amber/15 text-amber ring-amber/25",
  bull: "bg-bull/15 text-bull ring-bull/25",
  bear: "bg-bear/15 text-bear ring-bear/25",
};
export function Module({
  title, hint, icon = "flame", accent = "reddit", right, flush = false, className = "", bodyClassName, children,
}: {
  title: string; hint?: string; icon?: keyof typeof MICON; accent?: keyof typeof MACCENT;
  right?: React.ReactNode; flush?: boolean; className?: string; bodyClassName?: string; children: React.ReactNode;
}) {
  const Ic = MICON[icon] ?? IconFlame;
  const bodyCls = bodyClassName ?? (flush ? "overflow-hidden rounded-b-xl" : "p-5");
  return (
    <section className={`panel rounded-xl ${className}`}>
      <div className="flex shrink-0 items-center gap-2.5 px-5 pt-4 pb-3 border-b border-line">
        <span className={`grid place-items-center w-7 h-7 rounded-lg ring-1 ring-inset shrink-0 ${MACCENT[accent] ?? MACCENT.reddit}`}>
          <Ic className="w-4 h-4" />
        </span>
        <div className="min-w-0 flex-1">
          <h2 className="font-display font-bold text-cream text-[15px] tracking-tight leading-none">{title}</h2>
          {hint && <p className="mt-1 text-[11px] text-neutral-500 truncate">{hint}</p>}
        </div>
        {right && <div className="shrink-0">{right}</div>}
      </div>
      <div className={bodyCls}>{children}</div>
    </section>
  );
}

// 无边框统计条：一个面板内 N 格，用发丝线分隔（替代多个独立带边小卡）。
export function StatStrip({ items }: { items: { label: string; value: string; sub?: string; tone?: string }[] }) {
  return (
    <div className="panel rounded-xl grid grid-cols-2 sm:grid-cols-4 divide-x divide-y sm:divide-y-0 divide-line overflow-hidden">
      {items.map((s, i) => (
        <div key={i} className="px-4 py-3.5">
          <div className="text-[10px] uppercase tracking-wider text-neutral-500">{s.label}</div>
          <div className={`mt-1 font-display font-bold text-[20px] leading-none tabular ${s.tone ?? "text-cream"}`}>{s.value}</div>
          {s.sub && <div className="mt-1 text-[10px] text-neutral-600">{s.sub}</div>}
        </div>
      ))}
    </div>
  );
}

// Dune 式大数字计数器（醒目 KPI 行，单一大数字 + 标签）。
export function Counter({ label, value, sub, tone = "text-cream" }: { label: string; value: string; sub?: string; tone?: string }) {
  return (
    <div className="px-4 py-4">
      <div className="text-[11px] uppercase tracking-wider text-neutral-500">{label}</div>
      <div className={`mt-2 font-display font-extrabold text-[28px] sm:text-[32px] leading-none tabular ${tone}`}>{value}</div>
      {sub && <div className="mt-2 text-[11px] text-neutral-500 truncate">{sub}</div>}
    </div>
  );
}
export function Counters({ children }: { children: React.ReactNode }) {
  return <div className="panel rounded-xl grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 divide-x divide-y lg:divide-y-0 divide-line overflow-hidden">{children}</div>;
}

// 小统计块
export function StatTile({ label, value, sub, tone = "text-cream" }: { label: string; value: string; sub?: string; tone?: string }) {
  return (
    <div className="rounded-lg bg-white/[.012] ring-1 ring-inset ring-line px-3 py-2.5">
      <div className="text-[10px] uppercase tracking-wider text-neutral-500">{label}</div>
      <div className={`mt-1 font-display font-bold text-[19px] leading-none tabular ${tone}`}>{value}</div>
      {sub && <div className="mt-1 text-[10px] text-neutral-600">{sub}</div>}
    </div>
  );
}

// 升/降箭头
export function Arrow({ up, className = "" }: { up: boolean; className?: string }) {
  return <span className={`${up ? "text-bull" : "text-bear"} ${className}`}>{up ? "▲" : "▼"}</span>;
}

// 带符号变化量（绿涨红跌；invert=true 时颜色反转，如分歧/风险升=偏负）
export function Delta({ value, unit = "", digits = 2, invert = false }: { value: number; unit?: string; digits?: number; invert?: boolean }) {
  const good = invert ? value < 0 : value > 0;
  const cls = value === 0 ? "text-neutral-500" : good ? "text-bull" : "text-bear";
  return <span className={`font-mono tabular ${cls}`}>{value > 0 ? "+" : ""}{value.toFixed(digits)}{unit}</span>;
}

// 偏离度 σ 徽标（越大越红）
export function SigmaBadge({ sigma }: { sigma: number }) {
  const cls = sigma >= 4 ? "bg-bear/15 text-bear ring-bear/30" : sigma >= 2.5 ? "bg-amber/15 text-amber ring-amber/30" : "bg-white/[.06] text-neutral-300 ring-white/10";
  return <span className={`inline-flex items-center rounded-md px-1.5 py-0.5 text-[11px] font-mono font-semibold ring-1 ring-inset ${cls}`}>{sigma.toFixed(1)}σ</span>;
}

// 强度点（1..3）
export function Intensity({ n }: { n: number }) {
  return (
    <span className="inline-flex items-center gap-0.5">
      {[1, 2, 3].map((i) => (
        <span key={i} className={`w-1.5 h-1.5 rounded-full ${i <= n ? "bg-reddit" : "bg-white/10"}`} />
      ))}
    </span>
  );
}

// vs 常态条：填充=value/max，竖线=baseline 位置
export function VsBaselineBar({ value, baseline, max, color = "#57D7BA" }: { value: number; baseline: number; max: number; color?: string }) {
  const m = Math.max(max, value, baseline) || 1;
  const w = Math.min(100, (value / m) * 100);
  const b = Math.min(100, (baseline / m) * 100);
  return (
    <div className="relative h-2 w-full rounded-full bg-white/[.06] overflow-hidden">
      <div className="absolute inset-y-0 left-0 rounded-full" style={{ width: `${w}%`, background: color }} />
      <div className="absolute inset-y-0 w-px bg-cream/70" style={{ left: `${b}%` }} title="baseline" />
    </div>
  );
}

// 话题标签组
export function Chips({ items, lang, tone = "default" }: { items: Bi[]; lang: Locale; tone?: "default" | "bull" | "bear" }) {
  const cls = tone === "bull" ? "bg-bull/12 text-bull ring-bull/20" : tone === "bear" ? "bg-bear/12 text-bear ring-bear/20" : "bg-white/[.05] text-neutral-300 ring-white/10";
  return (
    <div className="flex flex-wrap gap-1.5">
      {items.map((t, i) => (
        <span key={i} className={`inline-flex items-center rounded-md px-2 py-0.5 text-[11.5px] ring-1 ring-inset ${cls}`}>{bi(t, lang)}</span>
      ))}
    </div>
  );
}

// 传导路径：地区流 + 累计时差，标注中文区
export function TransmissionFlow({ path, lang }: { path: { region: string; offsetHours: number; isCn: boolean }[]; lang: Locale }) {
  return (
    <div className="flex flex-wrap items-center gap-1.5">
      {path.map((p, i) => (
        <span key={p.region} className="flex items-center gap-1.5">
          {i > 0 && (
            <span className="font-mono text-[10px] text-neutral-600">
              →<span className="text-reddit">+{p.offsetHours - path[i - 1].offsetHours}h</span>
            </span>
          )}
          <span className={`inline-flex items-center gap-1 rounded-md px-1.5 py-1 text-[11.5px] ring-1 ring-inset ${p.isCn ? "bg-reddit/12 text-reddit ring-reddit/30" : "bg-white/[.05] text-neutral-300 ring-white/10"}`}>
            <span>{flag(p.region)}</span>
            <span className="font-medium">{regionLabel(p.region, lang)}</span>
            {i === 0 && <span className="text-[9px] text-neutral-500">{lang === "zh" ? "首发" : "first"}</span>}
          </span>
        </span>
      ))}
    </div>
  );
}

const TYPE_META: Record<string, { zh: string; en: string; cls: string }> = {
  earnings: { zh: "财报", en: "Earnings", cls: "bg-reddit/15 text-reddit ring-reddit/30" },
  product: { zh: "产品", en: "Product", cls: "bg-amber/15 text-amber ring-amber/30" },
  macro: { zh: "宏观", en: "Macro", cls: "bg-white/[.06] text-neutral-300 ring-white/10" },
  regulatory: { zh: "监管", en: "Regulatory", cls: "bg-bear/15 text-bear ring-bear/30" },
};
export function TypeBadge({ type, lang }: { type: string; lang: Locale }) {
  const m = TYPE_META[type] ?? TYPE_META.macro;
  return <span className={`inline-flex items-center rounded-full px-2 py-0.5 text-[11px] font-semibold ring-1 ring-inset ${m.cls}`}>{lang === "zh" ? m.zh : m.en}</span>;
}

export function Countdown({ days, lang }: { days: number; lang: Locale }) {
  return (
    <span className="inline-flex items-baseline gap-1">
      <span className="font-display font-extrabold text-cream text-xl tabular">{days}</span>
      <span className="text-[11px] text-neutral-500">{lang === "zh" ? "天后" : "days"}</span>
    </span>
  );
}

export function StageBadge({ stage, lang }: { stage: Bi; lang: Locale }) {
  const v = stage.en;
  const cls = v === "Overheated" ? "bg-bear/15 text-bear ring-bear/30" : v === "Heating" ? "bg-amber/15 text-amber ring-amber/30" : "bg-bull/15 text-bull ring-bull/30";
  return <span className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-[12px] font-semibold ring-1 ring-inset ${cls}`}>{bi(stage, lang)}</span>;
}

// 地区色点 + 名
export function RegionDot({ region, lang }: { region: string; lang: Locale }) {
  return <RegionBadge region={region} lang={lang} />;
}

export { regionColor, sentTextClass };
