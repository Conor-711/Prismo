"use client";

// 标的总览页顶部的两个排行榜：KOL「最看多 / 最看空」标的（各前 5）。
// 排序口径 = 近 14 天 KOL 每日净情绪之和（kol_sentiment_daily.net = 情绪×热度×相关性 加权），
// 与标的详情页的情绪折线同源、同信号。每行展示 净情绪 + 多空帖数占比条（透明可核）。
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { TickerLogo } from "./TickerLogo";
import { StanceBar } from "./Bits";
import { fmtCompact } from "@/lib/format";
import type { KolRank, KolSwing } from "@/lib/kolQueries";

const GREEN = "#57D7BA";
const RED = "#FF5C6C";
const AMBER = "#F2B544";

function Row({ r, rank, zh }: { r: KolRank; rank: number; zh: boolean }) {
  const name = zh ? r.nameZh || r.nameEn : r.nameEn || r.nameZh;
  const netColor = r.net > 0 ? GREEN : r.net < 0 ? RED : "#9aa0a6";
  return (
    <li>
      <LocaleLink
        href={`/tickers/${r.ticker}`}
        className="flex items-center gap-3 rounded-lg px-2 py-2 transition hover:bg-elevated/60"
      >
        <span className="w-4 shrink-0 text-center font-mono text-[12px] tabular text-neutral-600">{rank}</span>
        <TickerLogo ticker={r.ticker} size={26} />
        <div className="min-w-0 flex-1">
          <div className="flex items-baseline gap-1.5">
            <span className="font-mono text-[13px] font-semibold text-cream">{r.ticker}</span>
            <span className="min-w-0 truncate text-[11px] text-neutral-500">{name}</span>
          </div>
          {/* 多空帖数占比条 + 计数（看多绿 / 看空红） */}
          <div className="mt-1 flex items-center gap-2">
            <StanceBar bull={r.nBull} bear={r.nBear} neutral={0} className="max-w-[120px] flex-1" />
            <span className="shrink-0 text-[10px] tabular text-neutral-600">
              <span style={{ color: GREEN }}>{fmtCompact(r.nBull)}</span>
              {" · "}
              <span style={{ color: RED }}>{fmtCompact(r.nBear)}</span>
            </span>
          </div>
        </div>
        <span className="shrink-0 text-right font-mono text-[14px] font-bold tabular" style={{ color: netColor }}>
          {r.net > 0 ? "+" : ""}{fmtCompact(r.net)}
        </span>
      </LocaleLink>
    </li>
  );
}

function Board({ tone, rows, zh }: { tone: "bull" | "bear"; rows: KolRank[]; zh: boolean }) {
  const bull = tone === "bull";
  const title = bull ? (zh ? "KOL 最看多" : "Most bullish (KOL)") : (zh ? "KOL 最看空" : "Most bearish (KOL)");
  const accent = bull ? GREEN : RED;
  return (
    <div className="rounded-xl bg-card p-4 ring-1 ring-inset ring-line">
      <div className="mb-2 flex items-center gap-2">
        <span
          aria-hidden
          className="grid h-5 w-5 place-items-center rounded-md text-[12px] font-bold"
          style={{ background: `${accent}22`, color: accent }}
        >
          {bull ? "▲" : "▼"}
        </span>
        <span className="text-[13px] font-semibold text-cream">{title}</span>
        <span className="ml-auto text-[10px] text-neutral-600">{zh ? "近 14 天 · 净情绪" : "14d · net sentiment"}</span>
      </div>
      {rows.length ? (
        <ol className="-mx-2">
          {rows.map((r, i) => (
            <Row key={r.ticker} r={r} rank={i + 1} zh={zh} />
          ))}
        </ol>
      ) : (
        <p className="px-2 py-6 text-center text-[12px] text-neutral-600">{zh ? "暂无数据" : "No data yet"}</p>
      )}
    </div>
  );
}

// 「情绪变化最大」一行：看多占比 前7天→后7天 + Δpp（+绿转多 / −红转空）。
function SwingRow({ r, rank, zh }: { r: KolSwing; rank: number; zh: boolean }) {
  const name = zh ? r.nameZh || r.nameEn : r.nameEn || r.nameZh;
  const up = r.delta > 0;
  const dColor = up ? GREEN : RED;
  return (
    <li>
      <LocaleLink
        href={`/tickers/${r.ticker}`}
        className="flex items-center gap-3 rounded-lg px-2 py-2 transition hover:bg-elevated/60"
      >
        <span className="w-4 shrink-0 text-center font-mono text-[12px] tabular text-neutral-600">{rank}</span>
        <TickerLogo ticker={r.ticker} size={26} />
        <div className="min-w-0 flex-1">
          <div className="flex items-baseline gap-1.5">
            <span className="font-mono text-[13px] font-semibold text-cream">{r.ticker}</span>
            <span className="min-w-0 truncate text-[11px] text-neutral-500">{name}</span>
          </div>
          {/* 看多占比的迁移：前7天 → 后7天 */}
          <div className="mt-0.5 text-[10.5px] tabular text-neutral-600">
            {zh ? "看多占比 " : "bull "}
            <span className="text-neutral-400">{r.priorShare}%</span>
            <span className="px-1 text-neutral-600">→</span>
            <span style={{ color: dColor }}>{r.recentShare}%</span>
          </div>
        </div>
        <span className="shrink-0 text-right">
          <span className="font-mono text-[14px] font-bold tabular" style={{ color: dColor }}>
            {up ? "+" : ""}{r.delta}pp
          </span>
          <span className="block text-[10px]" style={{ color: dColor }}>
            {up ? (zh ? "转多" : "→ bull") : (zh ? "转空" : "→ bear")}
          </span>
        </span>
      </LocaleLink>
    </li>
  );
}

function SwingBoard({ rows, zh }: { rows: KolSwing[]; zh: boolean }) {
  return (
    <div className="rounded-xl bg-card p-4 ring-1 ring-inset ring-line">
      <div className="mb-2 flex items-center gap-2">
        <span
          aria-hidden
          className="grid h-5 w-5 place-items-center rounded-md text-[12px] font-bold"
          style={{ background: `${AMBER}22`, color: AMBER }}
        >
          ⇅
        </span>
        <span className="text-[13px] font-semibold text-cream">{zh ? "KOL 情绪变化最大" : "Biggest mood shift (KOL)"}</span>
        <span className="ml-auto text-[10px] text-neutral-600">{zh ? "近 14 天 · 看多占比 Δ" : "14d · Δ bull-share"}</span>
      </div>
      {rows.length ? (
        <ol className="-mx-2">
          {rows.map((r, i) => (
            <SwingRow key={r.ticker} r={r} rank={i + 1} zh={zh} />
          ))}
        </ol>
      ) : (
        <p className="px-2 py-6 text-center text-[12px] text-neutral-600">{zh ? "暂无数据" : "No data yet"}</p>
      )}
    </div>
  );
}

export function KolRankBoards({ bullish, bearish, swings }: { bullish: KolRank[]; bearish: KolRank[]; swings: KolSwing[] }) {
  const { lang } = useLocale();
  const zh = lang === "zh";
  if (!bullish.length && !bearish.length && !swings.length) return null;
  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <Board tone="bull" rows={bullish} zh={zh} />
      <Board tone="bear" rows={bearish} zh={zh} />
      <SwingBoard rows={swings} zh={zh} />
    </div>
  );
}
