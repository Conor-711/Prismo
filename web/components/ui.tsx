"use client";

import { LocaleLink } from "./i18n/LocaleLink";
import { useLocale } from "./i18n/LocaleProvider";
import { sentTextClass, stanceLabel } from "@/lib/format";
import { SnooAvatar } from "./reddit";
import { CommunityIcon } from "./CommunityIcon";
import { IconTrophy, IconPulse, IconTrend, IconFlame, IconLayers, IconDoc, IconWaves } from "./icons";

// 用户头像 = Reddit 风格的 Snoo（每个用户按名字确定性取色）。
export function Avatar({ name, size = 20 }: { name: string; size?: number }) {
  return <SnooAvatar name={name || "?"} size={size} />;
}

export function SubredditChip({ name, className = "" }: { name: string; className?: string }) {
  return (
    <span className={`inline-flex items-center gap-1.5 font-semibold text-neutral-300 ${className}`}>
      <CommunityIcon id={name} size={16} className="text-[9px]" />
      r/{name}
    </span>
  );
}

export function Panel({ children, className = "", style }: { children: React.ReactNode; className?: string; style?: React.CSSProperties }) {
  return <div className={`panel rounded-xl ${className}`} style={style}>{children}</div>;
}

export function Eyebrow({ children, color = "text-amber" }: { children: React.ReactNode; color?: string }) {
  return <div className={`text-[11px] font-semibold uppercase tracking-wider ${color}`}>{children}</div>;
}

// 编辑式页头：眉标 + 紧凑标题 + 底部发丝线 + 右侧可放 stat/操作。全站统一。
export function PageHeader({
  eyebrow,
  eyebrowColor = "text-reddit",
  title,
  subtitle,
  right,
}: {
  eyebrow: string;
  eyebrowColor?: string;
  title: string;
  subtitle?: string;
  right?: React.ReactNode;
}) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-x-6 gap-y-3 pb-4 border-b border-line">
      <div>
        <Eyebrow color={eyebrowColor}>{eyebrow}</Eyebrow>
        <h1 className="mt-1.5 font-display font-extrabold text-cream text-[22px] leading-none tracking-tight">{title}</h1>
        {subtitle && <p className="mt-2 text-sm text-neutral-500 max-w-2xl">{subtitle}</p>}
      </div>
      {right && <div className="shrink-0">{right}</div>}
    </div>
  );
}

// 页头右侧的数据胶囊（label + 大数字）。
export function HeaderStat({ label, value, tone = "text-cream" }: { label: string; value: string; tone?: string }) {
  return (
    <div className="px-4 py-2 rounded-lg ring-1 ring-inset ring-white/[.06] bg-white/[.012]">
      <div className="text-[10px] uppercase tracking-wider text-neutral-500">{label}</div>
      <div className={`mt-0.5 font-display font-bold text-lg tabular leading-none ${tone}`}>{value}</div>
    </div>
  );
}

// 每个分区的强调色 + 图标，避免所有看板「同一根橙条」造成的审美疲劳。
// 用字符串 key（可跨 server→client 边界），内部映射到颜色类与图标组件。
const ST_ACCENT: Record<string, { bar: string; chip: string }> = {
  reddit: { bar: "bg-reddit", chip: "bg-reddit/12 text-reddit ring-reddit/20" },
  amber: { bar: "bg-amber", chip: "bg-amber/15 text-amber ring-amber/20" },
  gold: { bar: "bg-gold", chip: "bg-gold/15 text-gold ring-gold/25" },
  bull: { bar: "bg-bull", chip: "bg-bull/15 text-bull ring-bull/20" },
  bear: { bar: "bg-bear", chip: "bg-bear/15 text-bear ring-bear/20" },
  neutral: { bar: "bg-neutral-500", chip: "bg-white/[.06] text-neutral-300 ring-white/10" },
};
const ST_ICON: Record<string, (p: { className?: string }) => JSX.Element> = {
  trophy: IconTrophy, pulse: IconPulse, trend: IconTrend, flame: IconFlame, layers: IconLayers, doc: IconDoc, waves: IconWaves,
};

export function SectionTitle({
  title,
  hint,
  href,
  accent = "reddit",
  icon,
}: {
  title: string;
  hint?: string;
  href?: string;
  accent?: keyof typeof ST_ACCENT;
  icon?: keyof typeof ST_ICON;
}) {
  const { dict } = useLocale();
  const a = ST_ACCENT[accent] ?? ST_ACCENT.reddit;
  const Ic = icon ? ST_ICON[icon] : undefined;
  return (
    <div className="flex items-center gap-3 mb-3">
      <div className="flex items-center gap-2 shrink-0">
        {Ic ? (
          <span className={`grid place-items-center w-6 h-6 rounded-lg ring-1 ring-inset ${a.chip}`}>
            <Ic className="w-3.5 h-3.5" />
          </span>
        ) : (
          <span className={`w-1 h-3.5 rounded-full ${a.bar}`} />
        )}
        <h2 className="font-display font-bold text-cream text-[15px] tracking-tight">{title}</h2>
      </div>
      <div className="h-px flex-1 bg-line/70" />
      {href ? (
        <LocaleLink href={href} className="text-xs text-neutral-500 hover:text-reddit transition shrink-0">
          {dict.common.all} →
        </LocaleLink>
      ) : hint ? (
        <span className="text-xs text-neutral-600 shrink-0">{hint}</span>
      ) : null}
    </div>
  );
}

export function SentPill({ stance, score, className = "" }: { stance?: string; score?: number; className?: string }) {
  const { lang } = useLocale();
  const s = stance ?? (score !== undefined ? (score > 0.15 ? "bull" : score < -0.15 ? "bear" : "neutral") : "neutral");
  const map: Record<string, string> = {
    bull: "bg-bull/12 text-bull",
    bear: "bg-bear/12 text-bear",
    neutral: "bg-neutral-500/12 text-neutral-400",
  };
  return (
    <span className={`inline-flex items-center gap-1 text-[11px] font-medium px-2 py-0.5 rounded-md ${map[s]} ${className}`}>
      <span className="w-1.5 h-1.5 rounded-full bg-current opacity-80" />
      {stanceLabel(s, lang)}
    </span>
  );
}

export function TickerChip({ ticker, size = "sm", base = "/ticker" }: { ticker: string; size?: "sm" | "xs"; base?: string }) {
  return (
    <LocaleLink
      href={`${base}/${ticker}`}
      className={`inline-flex items-center font-mono font-medium rounded-md bg-white/[.04] text-neutral-200 hover:bg-amber/15 hover:text-amber transition ring-1 ring-inset ring-white/8 ${
        size === "xs" ? "text-[11px] px-1.5 py-0.5" : "text-xs px-2 py-0.5"
      }`}
    >
      {ticker}
    </LocaleLink>
  );
}

export function ThemeTag({ children }: { children: React.ReactNode }) {
  return (
    <span className="text-[11px] px-2 py-0.5 rounded-md bg-gold/10 text-gold ring-1 ring-inset ring-gold/15">
      {children}
    </span>
  );
}

export function ScoreNum({ score }: { score: number }) {
  return <span className={`font-mono tabular ${sentTextClass(score)}`}>{score > 0 ? "+" : ""}{score.toFixed(2)}</span>;
}

export function MiniBar({ pct, color = "bg-amber" }: { pct: number; color?: string }) {
  return (
    <div className="h-1.5 w-full rounded-full bg-white/[.06] overflow-hidden">
      <div className={`h-full rounded-full ${color}`} style={{ width: `${Math.min(100, pct)}%` }} />
    </div>
  );
}
