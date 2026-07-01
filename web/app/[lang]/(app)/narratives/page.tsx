import type { Metadata } from "next";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { Panel } from "@/components/ui";
import { NarrativeMindshareAreaChart } from "@/components/prismo/NarrativeRotationCharts";
import { ViewportWorkspace } from "@/components/prismo/ViewportWorkspace";
import { fmtCompact, fmtPct, timeAgo } from "@/lib/format";
import {
  getNarrativeRotation,
  narrativeText,
  trendLabel,
  type NarrativeDay,
  type NarrativeLeader,
} from "@/lib/narrativeRotation";
import { defaultLocale, isLocale, type Locale } from "@/lib/i18n";

export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const zh = params.lang === "zh";
  return {
    title: zh ? "叙事轮动 · Prismo" : "Narrative rotation · Prismo",
    description: zh
      ? "跨社区固定板块叙事的热度排名、讨论占比与情绪变化。"
      : "Cross-community fixed sector narratives by rank, discussion share and sentiment rotation.",
  };
}

type BoardRow = NarrativeLeader & {
  currentShare: number;
  d1: number;
  d7: number;
  dWindow: number;
};

function shareAt(rows: NarrativeDay[], offsetFromEnd: number): number {
  if (!rows.length) return 0;
  const idx = Math.max(0, rows.length - 1 - offsetFromEnd);
  return rows[idx]?.share ?? 0;
}

function boardRows(leaders: NarrativeLeader[], series: Record<string, NarrativeDay[]>): BoardRow[] {
  return leaders
    .filter((row) => row.volume > 0)
    .map((row) => {
      const rows = series[row.id] ?? [];
      const currentShare = shareAt(rows, 0) || row.share;
      return {
        ...row,
        currentShare,
        d1: currentShare - shareAt(rows, 1),
        d7: currentShare - shareAt(rows, 7),
        dWindow: currentShare - shareAt(rows, rows.length - 1),
      };
    });
}

function Bps({ value }: { value: number }) {
  const bps = Math.round(value * 10000);
  const cls = bps === 0 ? "text-neutral-500" : bps > 0 ? "text-bull" : "text-bear";
  return (
    <span className={`font-mono tabular ${cls}`}>
      {bps > 0 ? "▲ " : bps < 0 ? "▼ " : ""}
      {bps === 0 ? "0" : Math.abs(bps)}bps
    </span>
  );
}

function Segment({ active = false, children }: { active?: boolean; children: React.ReactNode }) {
  return (
    <span className={`inline-flex h-7 items-center px-2.5 text-[10.5px] font-semibold ring-1 ring-inset ${
      active ? "bg-reddit/15 text-reddit ring-reddit/30" : "bg-white/[.025] text-neutral-500 ring-white/8"
    }`}>
      {children}
    </span>
  );
}

function NarrativeMoveBoard({
  title,
  rows,
  lang,
  positive,
  className = "",
}: {
  title: string;
  rows: BoardRow[];
  lang: Locale;
  positive: boolean;
  className?: string;
}) {
  const zh = lang === "zh";
  const sorted = [...rows].sort((a, b) => positive ? b.d1 - a.d1 : a.d1 - b.d1).slice(0, 8);
  return (
    <Panel className={`flex min-h-0 flex-col overflow-hidden ${className}`}>
      <div className="flex items-center justify-between gap-3 border-b border-line px-3 py-2.5">
        <h2 className="font-display text-[14px] font-bold text-cream">{title}</h2>
        <div className="inline-flex overflow-hidden rounded-md">
          <Segment active>{zh ? "绝对 bps" : "Absolute bps"}</Segment>
          <Segment>{zh ? "相对 %" : "Relative %"}</Segment>
        </div>
      </div>
      <div className="min-h-0 flex-1 overflow-hidden">
        <table className="w-full table-fixed text-[11.5px]">
          <thead>
            <tr className="text-neutral-500">
              <th className="w-[46%] py-2 pl-3 pr-2 text-left font-medium">{zh ? "名称" : "Name"}</th>
              <th className="w-[16%] px-1.5 py-2 text-right font-medium">{zh ? "当前" : "Current"}</th>
              <th className="w-[19%] px-1.5 py-2 text-right font-medium">Δ1D</th>
              <th className="w-[19%] py-2 pl-1.5 pr-3 text-right font-medium">Δ7D</th>
            </tr>
          </thead>
          <tbody>
            {sorted.map((row) => (
              <tr key={row.id} className="border-t border-line/70 transition hover:bg-white/[.025]">
                <td className="py-2 pl-3 pr-2">
                  <LocaleLink href={`/narratives/${row.slug}`} className="group flex items-center gap-2">
                    <span className="h-2 w-2 shrink-0 rounded-sm" style={{ background: row.color }} />
                    <span className="min-w-0 truncate font-semibold text-neutral-300 group-hover:text-reddit">
                      {narrativeText(row.title, lang)}
                    </span>
                  </LocaleLink>
                </td>
                <td className="px-1.5 py-2 text-right font-mono tabular text-neutral-300">{fmtPct(row.currentShare * 100, 2)}</td>
                <td className="px-1.5 py-2 text-right"><Bps value={row.d1} /></td>
                <td className="py-2 pl-1.5 pr-3 text-right"><Bps value={row.d7} /></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Panel>
  );
}

export default function NarrativesPage({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  const data = getNarrativeRotation();
  const active = data.leaderboard.filter((r) => r.volume > 0);
  const rows = boardRows(data.leaderboard, data.series);
  const top = active[0];

  return (
    <ViewportWorkspace className="grid min-h-0 grid-rows-[auto_minmax(0,1fr)] gap-4 overflow-hidden" bottomOffset={16}>
      <div className="flex min-h-0 flex-wrap items-end justify-between gap-x-6 gap-y-3 border-b border-line pb-3">
        <div className="min-w-0">
          <div className="text-[11px] font-semibold uppercase tracking-wider text-reddit">
            {zh ? "PRISMO · 叙事" : "PRISMO · Narratives"}
          </div>
          <div className="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1.5">
            <h1 className="font-display text-[22px] font-extrabold leading-none tracking-tight text-cream">Narrative Mindshare</h1>
            <span className="rounded-full bg-white/[.04] px-2 py-0.5 text-[10px] font-semibold text-neutral-500 ring-1 ring-inset ring-white/10">
              {data.window.start} → {data.window.end}
            </span>
            <span className="text-xs text-neutral-500 tabular">
              {zh ? "更新于 " : "Updated "}{timeAgo(data.updated_at, lang)}
            </span>
          </div>
          <p className="mt-1.5 max-w-3xl truncate text-sm text-neutral-500">
            {zh
              ? "固定板块叙事在跨社区讨论中的份额变化，用于观察哪类市场故事正在升温或降温。"
              : "Fixed sector narratives by their share of cross-community discussion, showing which market stories are gaining or fading."}
          </p>
        </div>

        <div className="flex shrink-0 items-center gap-3">
          {top && (
            <div className="hidden text-right xl:block">
              <div className="text-[10px] uppercase tracking-wider text-neutral-500">{zh ? "当前第一" : "Current leader"}</div>
              <div className="mt-0.5 max-w-[220px] truncate text-sm font-semibold text-cream">
                {narrativeText(top.title, lang)} · {fmtPct(top.share * 100, 1)}
              </div>
            </div>
          )}
          <div className="rounded-lg bg-white/[.012] px-3 py-2 text-right ring-1 ring-inset ring-white/[.06]">
            <div className="text-[10px] uppercase tracking-wider text-neutral-500">{zh ? "样本" : "Samples"}</div>
            <div className="mt-0.5 font-display text-lg font-bold leading-none tabular text-cream">
              {fmtCompact(data.summary.totalVolume)}
            </div>
          </div>
        </div>
      </div>

      {active.length === 0 ? (
        <Panel className="grid min-h-0 place-items-center p-10 text-center">
          <p className="text-sm text-neutral-400">{zh ? "暂无叙事轮动数据。" : "No narrative rotation data yet."}</p>
          <p className="mt-2 text-xs text-neutral-600">
            {zh ? "运行 " : "Run "}
            <code className="rounded bg-white/[.06] px-1.5 py-0.5 font-mono text-reddit">make narrative-rotation</code>
            {zh ? " 后重新构建。" : " then rebuild."}
          </p>
        </Panel>
      ) : (
        <div className="grid min-h-0 gap-3 lg:grid-cols-[390px_minmax(0,1fr)] 2xl:grid-cols-[420px_minmax(0,1fr)]">
          <aside className="grid min-h-0 grid-rows-2 gap-3">
            <NarrativeMoveBoard title={zh ? "Top Gainer" : "Top Gainer"} rows={rows} lang={lang} positive />
            <NarrativeMoveBoard title={zh ? "Top Loser" : "Top Loser"} rows={rows} lang={lang} positive={false} />
          </aside>

          <Panel className="flex min-h-0 flex-col overflow-hidden">
            <div className="flex shrink-0 flex-wrap items-start justify-between gap-4 border-b border-line px-5 py-3">
              <div className="min-w-0">
                <div className="flex items-center gap-2">
                  <h2 className="font-display text-[16px] font-bold text-cream">{zh ? "叙事讨论占比趋势" : "Narrative mindshare trend"}</h2>
                  <span className="rounded-full bg-white/[.05] px-2 py-0.5 text-[10px] font-semibold text-neutral-500 ring-1 ring-inset ring-white/10">
                    {data.summary.recentDays}D
                  </span>
                </div>
                <p className="mt-1.5 truncate text-xs text-neutral-500">
                  {top
                    ? `${zh ? "当前第一：" : "Current leader: "}${narrativeText(top.title, lang)} · ${fmtPct(top.share * 100, 1)} · ${trendLabel(top.trend, lang)}`
                    : zh ? "按每日讨论占比堆叠显示。" : "Stacked by daily discussion share."}
                </p>
              </div>

              <div className="flex flex-wrap items-center justify-end gap-3">
                <div className="inline-flex overflow-hidden rounded-md">
                  <Segment>{zh ? "热力图" : "Heatmap"}</Segment>
                  <Segment active>{zh ? "趋势" : "Trend"}</Segment>
                </div>
                <div className="inline-flex overflow-hidden rounded-md">
                  <Segment>7D</Segment>
                  <Segment>14D</Segment>
                  <Segment active>{data.summary.windowDays}D</Segment>
                </div>
              </div>
            </div>

            <div className="grid min-h-0 flex-1 grid-rows-[minmax(0,1fr)_auto] px-5 pb-3 pt-2">
              <div className="min-h-0">
                <NarrativeMindshareAreaChart leaders={data.leaderboard} series={data.series} height="100%" />
              </div>
              <div className="mt-2 flex shrink-0 flex-wrap items-center justify-between gap-3 border-t border-line/70 pt-2 text-[11px] text-neutral-600">
                <span>
                  {zh
                    ? "图中面积表示每个板块叙事在当日全部叙事讨论中的占比。"
                    : "Area represents each sector narrative's share of all classified narrative discussion on that day."}
                </span>
                <span className="font-mono tabular">
                  {data.window.start} → {data.window.end} · {fmtCompact(data.summary.totalVolume)} {zh ? "样本" : "samples"}
                </span>
              </div>
            </div>
          </Panel>
        </div>
      )}
    </ViewportWorkspace>
  );
}
