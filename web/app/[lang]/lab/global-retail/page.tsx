import type { Metadata } from "next";
import { getDictionary, isLocale, defaultLocale, type Locale } from "@/lib/i18n";
import { Panel, PageHeader, SectionTitle, SentPill, HeaderStat } from "@/components/ui";
import {
  getGrMeta, getGrTickers, getGrTickerRegions, getGrPosts, getGrUsPosts, GR_REGIONS,
  type GrTickerRow, type GrRegionCell, type GrPostRow,
} from "@/lib/globalQueries";
import { fmtInt, fmtCompact, timeAgo, sentTextClass } from "@/lib/format";
import { AsiaHeatmap, AsiaBubble, AsiaRadar } from "@/components/asia/AsiaCharts";

// 隐藏页：noindex、不进 sitemap、无导航入口。仅 URL /[lang]/lab/global-retail 直达。
export const metadata: Metadata = {
  title: "Global Retail Pulse",
  robots: { index: false, follow: false },
};

const REGION_COLOR: Record<string, string> = { us: "#E8552D", cn: "#2BB7B3", jp: "#4A9EE0", kr: "#E6B450", tw: "#B07CE6" };
const REGION_FLAG: Record<string, string> = { us: "🇺🇸", cn: "🇨🇳", jp: "🇯🇵", kr: "🇰🇷", tw: "🇹🇼" };
const fmtMood = (n: number) => (n > 0 ? "+" : "") + n.toFixed(2);

function moodCellClass(score: number): string {
  if (score >= 0.25) return "bg-bull/20 text-bull ring-bull/30";
  if (score >= 0.05) return "bg-bull/10 text-bull/90 ring-bull/15";
  if (score <= -0.25) return "bg-bear/20 text-bear ring-bear/30";
  if (score <= -0.05) return "bg-bear/10 text-bear/90 ring-bear/15";
  return "bg-white/[.04] text-neutral-300 ring-white/10";
}

export default function GlobalRetailPage({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const t = getDictionary(lang).global;
  const isZh = lang === "zh";

  const meta = getGrMeta();
  const tickers = getGrTickers();
  const cells = getGrTickerRegions();
  const hasData = tickers.length > 0;

  const REG_NAME: Record<string, string> = { us: t.regionUs, cn: t.regionCn, jp: t.regionJp, kr: t.regionKr, tw: t.regionTw };
  const REG_SRC: Record<string, string> = { us: t.srcUs, cn: t.srcCn, jp: t.srcJp, kr: t.srcKr, tw: t.srcTw };
  const nameOf = (tk: string) => { const x = tickers.find((r) => r.ticker === tk); return x ? (isZh ? x.name_zh : x.name_en) : tk; };

  // 按 ticker 索引各区单元
  const cellMap = new Map<string, Map<string, GrRegionCell>>();
  for (const c of cells) {
    if (!cellMap.has(c.ticker)) cellMap.set(c.ticker, new Map());
    cellMap.get(c.ticker)!.set(c.region, c);
  }
  const cellOf = (tk: string, r: string) => cellMap.get(tk)?.get(r);
  const regionsWithData = GR_REGIONS.filter((r) => cells.some((c) => c.region === r && c.post_count > 0));

  const byPosts = [...tickers].sort((a, b) => b.total_posts - a.total_posts);

  // ---- 四地区情绪概览 + 雷达 ----
  const regionAgg = GR_REGIONS.map((r) => {
    const rc = cells.filter((c) => c.region === r && c.post_count > 0);
    const posts = rc.reduce((a, c) => a + c.post_count, 0);
    const senti = posts ? rc.reduce((a, c) => a + c.sentiment_avg * c.post_count, 0) / posts : 0;
    const bullT = rc.filter((c) => c.mood_label === "bull").length;
    const bearT = rc.filter((c) => c.mood_label === "bear").length;
    const eng = rc.reduce((a, c) => a + c.engagement, 0);
    return { r, posts, senti: +senti.toFixed(3), bullT, bearT, tickers: rc.length, eng };
  }).filter((a) => a.posts > 0);
  const maxRP = Math.max(1, ...regionAgg.map((a) => a.posts));
  const maxBreadth = Math.max(1, ...regionAgg.map((a) => a.tickers));
  const maxEngPer = Math.max(0.01, ...regionAgg.map((a) => a.eng / Math.max(1, a.posts)));
  const radarInd = [
    { name: t.radarSentiment, max: 1 }, { name: t.radarVolume, max: 1 }, { name: t.radarBull, max: 1 },
    { name: t.radarBreadth, max: 1 }, { name: t.radarEngage, max: 1 },
  ];
  const radarSeries = regionAgg.map((a) => ({
    name: REG_NAME[a.r], color: REGION_COLOR[a.r],
    value: [
      +((a.senti + 1) / 2).toFixed(2), +(a.posts / maxRP).toFixed(2),
      +(a.bullT / Math.max(1, a.bullT + a.bearT)).toFixed(2), +(a.tickers / maxBreadth).toFixed(2),
      +((a.eng / Math.max(1, a.posts)) / maxEngPer).toFixed(2),
    ],
  }));

  // ---- 共识 / 分歧 ----
  const allBull = byPosts.filter((t2) => t2.consensus === "all_bull")
    .sort((a, b) => b.regions_present - a.regions_present || b.avg_sentiment - a.avg_sentiment);
  const allBear = byPosts.filter((t2) => t2.consensus === "all_bear")
    .sort((a, b) => b.regions_present - a.regions_present || a.avg_sentiment - b.avg_sentiment);
  const divergent = [...tickers]
    .filter((t2) => t2.consensus === "divergent" || (t2.regions_present >= 3 && t2.spread >= 0.35))
    .sort((a, b) => b.spread - a.spread).slice(0, 10);

  // ---- 热力（标的×区）----
  const heatTickers = byPosts.slice(0, 22);
  const heatCells: [number, number, number][] = [];
  heatTickers.forEach((tk, yi) => regionsWithData.forEach((r, xi) => {
    const c = cellOf(tk.ticker, r);
    if (c && c.post_count > 0) heatCells.push([xi, yi, c.sentiment_avg]);
  }));

  // ---- 定位气泡（按共识分色/图例）----
  const CONS: Record<string, { label: string; color: string }> = {
    all_bull: { label: t.allBull, color: "#24B47E" }, all_bear: { label: t.allBear, color: "#F0556E" },
    divergent: { label: t.consensusTag.divergent, color: "#E6B450" },
    mixed: { label: t.consensusTag.mixed, color: "#7a8a96" }, sparse: { label: t.consensusTag.sparse, color: "#5a5a62" },
  };
  const bubble = byPosts.filter((t2) => t2.total_posts > 0).map((t2) => ({
    name: t2.ticker, x: Math.round(t2.avg_sentiment * 100), y: t2.total_posts,
    size: t2.regions_present * t2.regions_present, color: (CONS[t2.consensus] || CONS.mixed).color,
    market: (CONS[t2.consensus] || CONS.mixed).label,
  }));

  const maxVol = Math.max(1, ...byPosts.map((t2) => t2.total_posts));

  // ---- 标的明细（Top 12，逐区代表帖）----
  const detailTickers = byPosts.filter((t2) => t2.total_posts > 0).slice(0, 12);
  const repPosts = new Map<string, Record<string, GrPostRow | undefined>>();
  for (const tk of detailTickers) {
    const rec: Record<string, GrPostRow | undefined> = {};
    rec.us = getGrUsPosts(tk.ticker, 1)[0];
    rec.cn = getGrPosts("cn", tk.ticker, 1)[0];
    rec.jp = getGrPosts("jp", tk.ticker, 1)[0];
    rec.kr = getGrPosts("kr", tk.ticker, 1)[0];
    rec.tw = getGrPosts("tw", tk.ticker, 1)[0];
    repPosts.set(tk.ticker, rec);
  }

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow={t.eyebrow} eyebrowColor="text-amber" title={t.title} subtitle={t.subtitle}
        right={hasData ? (
          <div className="flex gap-2 flex-wrap">
            <HeaderStat label={t.statTickers} value={String(meta.tickers)} />
            <HeaderStat label={t.statPosts} value={fmtInt(meta.posts)} />
            <HeaderStat label={t.statRegions} value={String(Math.max(meta.regions, regionsWithData.length))} />
            <HeaderStat label={t.weekOf} value={t.window14} />
          </div>
        ) : undefined}
      />

      <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5 text-[11px] text-neutral-500">
        {GR_REGIONS.map((r) => (
          <span key={r} className="inline-flex items-center gap-1">{REGION_FLAG[r]} {REG_NAME[r]} · {REG_SRC[r]}</span>
        ))}
        <span className="text-neutral-600">· {t.disclaimer}</span>
      </div>

      {!hasData ? (
        <Panel className="p-10 text-center text-neutral-500 text-sm">{t.empty}</Panel>
      ) : (
        <>
          {/* 四地区情绪概览 + 雷达 */}
          <div className="grid lg:grid-cols-[1.3fr_1fr] gap-4 items-stretch">
            <Panel className="p-5">
              <SectionTitle title={t.regionMoodTitle} hint={t.regionMoodHint} accent="reddit" icon="layers" />
              <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
                {regionAgg.map((a) => (
                  <div key={a.r} className={`rounded-xl ring-1 ring-inset p-3 ${moodCellClass(a.senti)}`}>
                    <div className="flex items-center gap-1.5 text-xs font-semibold text-cream/90">
                      <span className="text-base">{REGION_FLAG[a.r]}</span> {REG_NAME[a.r]}
                    </div>
                    <div className="font-mono font-bold text-xl tabular mt-1.5 leading-none">{fmtMood(a.senti)}</div>
                    <div className="text-[10px] text-neutral-400 mt-1.5 tabular">
                      📝 {fmtInt(a.posts)} · <span className="text-bull/80">▲{a.bullT}</span> <span className="text-bear/80">▼{a.bearT}</span>
                    </div>
                  </div>
                ))}
              </div>
            </Panel>
            <Panel className="p-5">
              <SectionTitle title={t.radarTitle} hint={t.radarHint} accent="gold" icon="trend" />
              <AsiaRadar indicators={radarInd} series={radarSeries} height={250} />
            </Panel>
          </div>

          {/* 跨区情绪热力 */}
          {heatCells.length > 0 && (
            <Panel className="p-5">
              <SectionTitle title={t.heatTitle} hint={t.heatHint} accent="amber" icon="pulse" />
              <AsiaHeatmap
                rawX x={regionsWithData.map((r) => `${REGION_FLAG[r]} ${REG_NAME[r]}`)}
                y={heatTickers.map((tk) => tk.ticker)} cells={heatCells}
                height={90 + heatTickers.length * 22}
              />
            </Panel>
          )}

          {/* 四地共识：共同看多 / 共同看空 */}
          <Panel className="p-5">
            <SectionTitle title={t.consensusTitle} hint={t.consensusHint} accent="bull" icon="trophy" />
            <div className="grid md:grid-cols-2 gap-x-8 gap-y-2">
              <div>
                <div className="text-[11px] font-semibold text-bull mb-2">▲ {t.allBull}</div>
                {allBull.length ? allBull.map((tk) => <ConsensusRow key={tk.ticker} tk={tk} cellOf={cellOf} nameOf={nameOf} t={t} />)
                  : <div className="text-xs text-neutral-600 py-2">—</div>}
              </div>
              <div>
                <div className="text-[11px] font-semibold text-bear mb-2">▼ {t.allBear}</div>
                {allBear.length ? allBear.map((tk) => <ConsensusRow key={tk.ticker} tk={tk} cellOf={cellOf} nameOf={nameOf} t={t} />)
                  : <div className="text-xs text-neutral-600 py-2">—</div>}
              </div>
            </div>
          </Panel>

          {/* 地区分歧 */}
          {divergent.length > 0 && (
            <Panel className="p-5">
              <SectionTitle title={t.divergenceTitle} hint={t.divergenceHint} accent="reddit" icon="flame" />
              <div className="space-y-2.5">
                {divergent.map((tk) => <DivergenceRow key={tk.ticker} tk={tk} cellOf={cellOf} nameOf={nameOf} t={t} regName={REG_NAME} />)}
              </div>
            </Panel>
          )}

          {/* 定位气泡 + 热度榜 */}
          <div className="grid lg:grid-cols-2 gap-4 items-start">
            <Panel className="p-5">
              <SectionTitle title={t.bubbleTitle} hint={t.bubbleHint} accent="gold" icon="layers" />
              <AsiaBubble points={bubble} xName={t.bubbleX} yName={t.bubbleY} height={320} />
            </Panel>
            <Panel className="p-5">
              <SectionTitle title={t.volumeTitle} hint={t.volumeHint} accent="amber" icon="trophy" />
              <div className="space-y-2">
                {byPosts.slice(0, 12).map((tk) => {
                  const segs = GR_REGIONS.map((r) => ({ r, n: cellOf(tk.ticker, r)?.post_count ?? 0 }));
                  return (
                    <div key={tk.ticker} className="grid grid-cols-[64px_1fr_44px] items-center gap-2.5">
                      <span className="font-mono text-xs text-cream truncate">{tk.ticker}</span>
                      <div className="h-3.5 w-full rounded-full bg-white/[.05] overflow-hidden flex"
                        title={segs.map((s) => `${REG_NAME[s.r]} ${s.n}`).join(" · ")}>
                        {segs.map((s) => s.n > 0 ? (
                          <div key={s.r} className="h-full" style={{ width: `${(s.n / maxVol) * 100}%`, background: REGION_COLOR[s.r] }} />
                        ) : null)}
                      </div>
                      <span className="font-mono text-xs text-neutral-400 tabular text-right">{fmtInt(tk.total_posts)}</span>
                    </div>
                  );
                })}
              </div>
              <div className="mt-3 flex flex-wrap gap-3 text-[10px] text-neutral-500">
                {GR_REGIONS.map((r) => (
                  <span key={r} className="inline-flex items-center gap-1">
                    <i className="w-2.5 h-2.5 rounded-sm inline-block" style={{ background: REGION_COLOR[r] }} /> {REG_NAME[r]}
                  </span>
                ))}
              </div>
            </Panel>
          </div>

          {/* 标的 · 四地区明细 */}
          <div>
            <SectionTitle title={t.detailTitle} hint={t.detailHint} accent="reddit" icon="layers" />
            <div className="space-y-4">
              {detailTickers.map((tk) => (
                <Panel key={tk.ticker} className="p-4">
                  <div className="flex items-baseline gap-2 mb-3 flex-wrap">
                    <span className="font-display font-bold text-cream text-[15px]">{nameOf(tk.ticker)}</span>
                    <span className="font-mono text-xs text-neutral-500">{tk.ticker}</span>
                    <ConsensusBadge tk={tk} t={t} />
                    <span className="ml-auto text-[11px] text-neutral-500 tabular">📝 {fmtInt(tk.total_posts)} · {tk.regions_present} {t.regionUnit}</span>
                  </div>
                  <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
                    {GR_REGIONS.map((r) => (
                      <RegionCol key={r} region={r} cell={cellOf(tk.ticker, r)} post={repPosts.get(tk.ticker)?.[r]}
                        regName={REG_NAME} regSrc={REG_SRC} t={t} isZh={isZh} lang={lang} />
                    ))}
                  </div>
                </Panel>
              ))}
            </div>
          </div>
        </>
      )}
    </div>
  );
}

// 四区情绪小点（mood 颜色，缺数据=灰）
function Dots({ tk, cellOf }: { tk: GrTickerRow; cellOf: (t: string, r: string) => GrRegionCell | undefined }) {
  return (
    <span className="inline-flex gap-1">
      {GR_REGIONS.map((r) => {
        const c = cellOf(tk.ticker, r);
        const cls = !c || c.post_count === 0 ? "bg-white/10"
          : c.mood_label === "bull" ? "bg-bull" : c.mood_label === "bear" ? "bg-bear" : "bg-neutral-500";
        return <i key={r} title={`${r}${c ? " " + fmtMood(c.sentiment_avg) : ""}`} className={`w-2.5 h-2.5 rounded-full inline-block ${cls}`} />;
      })}
    </span>
  );
}

function ConsensusRow({ tk, cellOf, nameOf, t }: { tk: GrTickerRow; cellOf: any; nameOf: any; t: any }) {
  return (
    <div className="flex items-center gap-2 py-1.5 border-b border-line/40 last:border-0">
      <span className="font-mono text-xs text-cream w-14 truncate">{tk.ticker}</span>
      <span className="text-[11px] text-neutral-400 flex-1 truncate">{nameOf(tk.ticker)}</span>
      <Dots tk={tk} cellOf={cellOf} />
      <span className="text-[10px] text-neutral-600 tabular w-14 text-right" title={t.agree}>{tk.regions_present} {t.regionUnit}</span>
      <span className={`font-mono text-xs tabular w-12 text-right ${sentTextClass(tk.avg_sentiment)}`}>{fmtMood(tk.avg_sentiment)}</span>
    </div>
  );
}

function DivergenceRow({ tk, cellOf, nameOf, t, regName }: { tk: GrTickerRow; cellOf: any; nameOf: any; t: any; regName: Record<string, string> }) {
  const dr = tk.divergent_region;
  const drCell = dr ? cellOf(tk.ticker, dr) : undefined;
  const others = GR_REGIONS.filter((r) => r !== dr).map((r) => cellOf(tk.ticker, r)).filter((c: any) => c && c.post_count > 0) as GrRegionCell[];
  const othersAvg = others.length ? others.reduce((a, c) => a + c.sentiment_avg, 0) / others.length : 0;
  return (
    <div className="flex items-center gap-2.5 py-1.5 border-b border-line/40 last:border-0 text-xs flex-wrap">
      <span className="font-mono text-cream w-14 truncate">{tk.ticker}</span>
      <Dots tk={tk} cellOf={cellOf} />
      {dr && drCell ? (
        <span className="text-[11px] text-neutral-300">
          <span className="text-amber font-semibold">{t.contrarianIn} {REGION_FLAG[dr]}{regName[dr]}</span>
          <span className={`font-mono ml-1 ${sentTextClass(drCell.sentiment_avg)}`}>{fmtMood(drCell.sentiment_avg)}</span>
          <span className="text-neutral-600"> {t.vsRest} </span>
          <span className={`font-mono ${sentTextClass(othersAvg)}`}>{fmtMood(othersAvg)}</span>
        </span>
      ) : <span className="text-[11px] text-neutral-500">{nameOf(tk.ticker)}</span>}
      <span className="ml-auto inline-flex items-center gap-1.5">
        <span className="text-[10px] text-neutral-600">{t.spreadLabel}</span>
        <span className="font-mono font-bold tabular text-amber">{tk.spread.toFixed(2)}</span>
      </span>
    </div>
  );
}

function ConsensusBadge({ tk, t }: { tk: GrTickerRow; t: any }) {
  const c = tk.consensus;
  if (!c || c === "sparse") return null;
  const cls = c === "all_bull" ? "bg-bull/12 text-bull ring-bull/25"
    : c === "all_bear" ? "bg-bear/12 text-bear ring-bear/25"
    : c === "divergent" ? "bg-amber/12 text-amber ring-amber/25" : "bg-white/[.05] text-neutral-400 ring-white/10";
  return <span className={`text-[9px] font-bold uppercase tracking-wider px-1.5 py-0.5 rounded ring-1 ring-inset ${cls}`}>{t.consensusTag[c] ?? c}</span>;
}

// 单区列（标的明细）
function RegionCol({ region, cell, post, regName, regSrc, t, isZh, lang }: {
  region: string; cell?: GrRegionCell; post?: GrPostRow; regName: Record<string, string>; regSrc: Record<string, string>;
  t: any; isZh: boolean; lang: Locale;
}) {
  const has = cell && cell.post_count > 0;
  return (
    <div className="rounded-lg bg-white/[.015] ring-1 ring-inset ring-white/[.05] p-2.5 space-y-2">
      <div className="flex items-center justify-between">
        <span className="text-[11px] font-semibold text-neutral-300">{REGION_FLAG[region]} {regName[region]}</span>
        {has && <span className={`font-mono text-xs tabular font-bold ${sentTextClass(cell!.sentiment_avg)}`}>{fmtMood(cell!.sentiment_avg)}</span>}
      </div>
      {has ? (
        <>
          <div className="h-1.5 w-full rounded-full overflow-hidden flex bg-white/[.05]">
            <div className="bg-bull" style={{ width: `${cell!.bull_pct}%` }} />
            <div className="bg-neutral-600" style={{ width: `${cell!.neutral_pct}%` }} />
            <div className="bg-bear" style={{ width: `${cell!.bear_pct}%` }} />
          </div>
          <div className="text-[10px] text-neutral-500 tabular">📝 {fmtInt(cell!.post_count)} · {regSrc[region]}</div>
          {post && (
            <div className="rounded-md bg-white/[.02] ring-1 ring-inset ring-white/[.05] px-2 py-1.5">
              <div className="flex items-center gap-1.5 mb-1">
                <SentPill stance={post.stance} score={post.sentiment} />
                {post.created && <span className="ml-auto text-[9px] text-neutral-600 tabular">{timeAgo(post.created, lang)}</span>}
              </div>
              <p className="text-[11px] leading-snug text-neutral-300 line-clamp-3">{post.body || post.title || "—"}</p>
              <div className="flex items-center gap-2 mt-1 text-[9px] text-neutral-600 tabular">
                {post.likes > 0 && <span>👍{fmtCompact(post.likes)}</span>}
                {post.comments > 0 && <span>💬{fmtCompact(post.comments)}</span>}
                {post.url && <a href={post.url} target="_blank" rel="noopener noreferrer nofollow" className="ml-auto hover:text-amber transition">{t.viewSource} ↗</a>}
              </div>
            </div>
          )}
        </>
      ) : (
        <div className="py-3 text-center text-[10px] text-neutral-600">{t.noRegion}</div>
      )}
    </div>
  );
}
