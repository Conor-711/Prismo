"use client";

// 投资者榜单：X / YouTube / Reddit / 雪球 四平台的活跃投资者，按影响力（互动/播放）排名。
// 顶部平台过滤：「全部」= 每平台前若干名预览（可点进单平台看全部）；选中某平台 = 该平台完整榜单。
import { useState } from "react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { Panel } from "@/components/ui";
import { fmtCompact } from "@/lib/format";
import { Avatar, SOURCE, SOURCE_ORDER } from "./kolShared";
import type { Investor, InvestorBoard as Board } from "@/lib/investorQueries";
import type { KolSource } from "@/lib/mockDetail";

const PREVIEW = 6; // 「全部」视图下每平台预览名额

const UNIT: Record<KolSource, { zh: string; en: string }> = {
  x: { zh: "推", en: "posts" },
  youtube: { zh: "视频", en: "videos" },
  reddit: { zh: "帖", en: "posts" },
  xueqiu: { zh: "帖", en: "posts" },
};
const metricLabel = (src: KolSource, zh: boolean) =>
  src === "youtube" ? (zh ? "播放" : "views") : zh ? "互动" : "interactions";

function Card({ inv, rank }: { inv: Investor; rank: number }) {
  const { lang } = useLocale();
  const zh = lang === "zh";
  const c = SOURCE[inv.source].color;
  return (
    <div className="flex items-center gap-3 rounded-xl bg-card px-3.5 py-3 ring-1 ring-inset ring-line transition hover:ring-white/15">
      <span className="w-5 shrink-0 text-center font-mono text-[15px] font-bold tabular" style={{ color: rank <= 3 ? c : "#6b6d70" }}>
        {rank}
      </span>
      <Avatar src={inv.avatar} color={c} name={inv.name} size={40} />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          {inv.url ? (
            <a
              href={inv.url}
              target="_blank"
              rel="noopener noreferrer"
              className="min-w-0 truncate font-semibold text-cream transition hover:text-neutral-300"
            >
              {inv.name}
            </a>
          ) : (
            <span className="min-w-0 truncate font-semibold text-cream">{inv.name}</span>
          )}
          <span className="shrink-0 rounded px-1.5 py-px text-[10px] font-medium" style={{ background: `${c}22`, color: c }}>
            {SOURCE[inv.source].label}
          </span>
        </div>
        {inv.tickers.length > 0 && (
          <div className="mt-1.5 flex flex-wrap items-center gap-1">
            {inv.tickers.slice(0, 5).map((t) => (
              <LocaleLink
                key={t}
                href={`/tickers/${t}`}
                className="rounded bg-elevated px-1.5 py-px font-mono text-[10.5px] text-neutral-400 transition hover:text-cream"
              >
                {t}
              </LocaleLink>
            ))}
            {inv.tickerCount > 5 && <span className="text-[10.5px] text-neutral-600">+{inv.tickerCount - 5}</span>}
          </div>
        )}
      </div>
      <div className="shrink-0 text-right">
        <div className="font-mono text-[15px] font-bold tabular text-cream">{fmtCompact(inv.metric)}</div>
        <div className="text-[10px] uppercase tracking-wide text-neutral-500">{metricLabel(inv.source, zh)}</div>
        <div className="mt-0.5 text-[10.5px] text-neutral-600">
          {fmtCompact(inv.posts)} {zh ? UNIT[inv.source].zh : UNIT[inv.source].en}
        </div>
      </div>
    </div>
  );
}

function FilterChip({
  on,
  onClick,
  label,
  color,
  count,
}: {
  on: boolean;
  onClick: () => void;
  label: string;
  color?: string;
  count?: number;
}) {
  return (
    <button
      onClick={onClick}
      className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-[13px] font-medium ring-1 ring-inset transition ${
        on ? "bg-elevated text-cream ring-white/15" : "text-neutral-400 ring-line hover:bg-white/[.04] hover:text-cream"
      }`}
    >
      {color && <span className="h-2 w-2 rounded-full" style={{ background: color, opacity: on ? 1 : 0.5 }} />}
      {label}
      {typeof count === "number" && <span className="font-mono text-[11px] tabular text-neutral-500">{count}</span>}
    </button>
  );
}

export function InvestorBoardView({ board }: { board: Board }) {
  const { lang, dict } = useLocale();
  const zh = lang === "zh";
  const t = dict.investors;
  const [active, setActive] = useState<"all" | KolSource>("all");

  const total = SOURCE_ORDER.reduce((n, s) => n + board[s].length, 0);
  if (total === 0) {
    return (
      <Panel className="p-10 text-center">
        <p className="text-sm text-neutral-400">{t.empty}</p>
        <p className="mt-2 text-xs text-neutral-600">{t.emptyDesc}</p>
      </Panel>
    );
  }

  const sections: KolSource[] = active === "all" ? SOURCE_ORDER : [active];

  return (
    <div className="space-y-7">
      <div className="flex flex-wrap gap-2">
        <FilterChip on={active === "all"} onClick={() => setActive("all")} label={t.all} />
        {SOURCE_ORDER.map((s) => (
          <FilterChip
            key={s}
            on={active === s}
            onClick={() => setActive(s)}
            color={SOURCE[s].color}
            label={SOURCE[s].label}
            count={board[s].length}
          />
        ))}
      </div>

      {sections.map((s) => {
        const full = board[s];
        if (!full.length) return null;
        const preview = active === "all";
        const list = preview ? full.slice(0, PREVIEW) : full;
        return (
          <section key={s}>
            <div className="mb-3 flex items-center gap-2.5">
              <span className="h-2.5 w-2.5 rounded-full" style={{ background: SOURCE[s].color }} />
              <h2 className="font-display text-[15px] font-bold text-cream">{SOURCE[s].label}</h2>
              <span className="text-[12px] text-neutral-500">
                {full.length} {t.unit}
              </span>
              {preview && full.length > PREVIEW && (
                <button onClick={() => setActive(s)} className="ml-auto text-[12px] text-neutral-500 transition hover:text-cream">
                  {t.viewAll} →
                </button>
              )}
            </div>
            <div className="grid gap-2.5 lg:grid-cols-2">
              {list.map((inv, i) => (
                <Card key={inv.id} inv={inv} rank={i + 1} />
              ))}
            </div>
          </section>
        );
      })}
    </div>
  );
}
