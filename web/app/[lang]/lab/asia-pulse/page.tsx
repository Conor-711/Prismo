import type { Metadata } from "next";
import { getDictionary, isLocale, defaultLocale, type Locale } from "@/lib/i18n";
import { Panel, PageHeader, SectionTitle, SentPill, ThemeTag, HeaderStat } from "@/components/ui";
import {
  getAsiaSummaries, getAsiaPosts, getAsiaMeta, getAsiaVolume, getAsiaDaily,
  getAsiaDailyByTicker, getAsiaTickerSeries, getAsiaMovers, getAsiaTwBreakdown,
  getAsiaSentiHeat, getAsiaEngagement, getAsiaVerifiedSplit, getAsiaJpSelfRating, getAsiaThemeStance,
  type AsiaSummary, type AsiaPostRow, type AsiaVolumeRow,
} from "@/lib/asiaQueries";
import { fmtInt, fmtCompact, timeAgo, sentTextClass } from "@/lib/format";
import {
  AsiaComboChart, AsiaMultiLine, AsiaDivergingBars, AsiaHeatmap, AsiaBubble, AsiaRadar, AsiaPairedBars,
} from "@/components/asia/AsiaCharts";

const TICKER_COLOR: Record<string, string> = { NVDA: "#76B900", MU: "#4A9EE0", NOK: "#B07CE6", SPCX: "#FF8717" };

// 隐藏页：不进 sitemap、无导航入口、noindex。仅通过 URL /[lang]/lab/asia-pulse 直达。
export const metadata: Metadata = {
  title: "Asia Retail Pulse",
  robots: { index: false, follow: false },
};

const TICKERS = [
  { key: "NVDA", zh: "英伟达", en: "NVIDIA" },
  { key: "MU", zh: "美光", en: "Micron" },
  { key: "NOK", zh: "诺基亚", en: "Nokia" },
  { key: "SPCX", zh: "SpaceX", en: "SpaceX" },
] as const;
const MARKETS = ["jp", "kr"] as const;
const MOOD_KEY: Record<string, "moodBull" | "moodBear" | "moodNeutral" | "moodMixed"> = {
  bull: "moodBull", bear: "moodBear", neutral: "moodNeutral", mixed: "moodMixed",
};

// 情绪 → 热力色（方向=色相，强度=深浅）
function moodCellClass(score: number): string {
  if (score >= 0.25) return "bg-bull/20 text-bull ring-bull/30";
  if (score >= 0.08) return "bg-bull/10 text-bull/90 ring-bull/15";
  if (score <= -0.25) return "bg-bear/20 text-bear ring-bear/30";
  if (score <= -0.08) return "bg-bear/10 text-bear/90 ring-bear/15";
  return "bg-white/[.04] text-neutral-300 ring-white/10";
}
const fmtMood = (n: number) => (n > 0 ? "+" : "") + n.toFixed(2);
const dayMD = (d: string) => d.slice(5).replace("-", "/");

export default function AsiaPulsePage({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const t = getDictionary(lang).asia;
  const isZh = lang === "zh";

  const meta = getAsiaMeta();
  const sumMap = new Map<string, AsiaSummary>(getAsiaSummaries().map((s) => [`${s.market}:${s.ticker}`, s]));
  const volMap = new Map<string, AsiaVolumeRow>(getAsiaVolume().map((v) => [`${v.market}:${v.ticker}`, v]));
  const daily = getAsiaDaily(7);
  const postMap = new Map<string, AsiaPostRow[]>();
  for (const m of MARKETS) for (const tk of TICKERS) postMap.set(`${m}:${tk.key}`, getAsiaPosts(m, tk.key, 2));

  const nameOf = (k: string) => {
    if (k === "TWSTOCK") return isZh ? "台股" : "TW";
    const x = TICKERS.find((t2) => t2.key === k); return x ? (isZh ? x.zh : x.en) : k;
  };
  const hasData = meta.posts > 0;

  // 每标的：综合情绪 + 声量 + 分歧
  const perTicker = TICKERS.map((tk) => {
    const jp = sumMap.get(`jp:${tk.key}`);
    const kr = sumMap.get(`kr:${tk.key}`);
    const moods = [jp?.mood_score, kr?.mood_score].filter((x): x is number => typeof x === "number");
    const combined = moods.length ? moods.reduce((a, b) => a + b, 0) / moods.length : 0;
    const volJp = volMap.get(`jp:${tk.key}`)?.n ?? 0;
    const volKr = volMap.get(`kr:${tk.key}`)?.n ?? 0;
    const divergence = jp && kr ? Math.abs(jp.mood_score - kr.mood_score) : null;
    return { tk, jp, kr, combined, volJp, volKr, vol: volJp + volKr, divergence };
  });
  const maxVol = Math.max(1, ...perTicker.map((p) => p.vol));
  const maxDaily = Math.max(1, ...daily.map((d) => d.total));

  // 主题热度聚合
  const themeCount = new Map<string, number>();
  for (const s of sumMap.values()) for (const th of s.top_themes) themeCount.set(th, (themeCount.get(th) ?? 0) + 1);
  const topThemes = [...themeCount.entries()].sort((a, b) => b[1] - a[1]).slice(0, 10);

  const range = meta.firstDay && meta.lastDay ? `${dayMD(meta.firstDay)}–${dayMD(meta.lastDay)}` : "—";

  // 趋势 / 变化 / 价格 数据
  const dayTick = getAsiaDailyByTicker();
  const trendDays = [...new Set(dayTick.map((d) => d.day))].sort();
  const dtLook = new Map(dayTick.map((d) => [`${d.ticker}:${d.day}`, d]));
  const volSeries = TICKERS.map((tk) => ({ name: nameOf(tk.key), color: TICKER_COLOR[tk.key], data: trendDays.map((d) => dtLook.get(`${tk.key}:${d}`)?.vol ?? 0) }));
  const sentiSeries = TICKERS.map((tk) => ({ name: nameOf(tk.key), color: TICKER_COLOR[tk.key], data: trendDays.map((d) => { const r = dtLook.get(`${tk.key}:${d}`); return r && r.sentiN ? r.senti : null; }) }));
  const combo = new Map(TICKERS.map((tk) => [tk.key, getAsiaTickerSeries(tk.key, 10)]));
  const movers = getAsiaMovers(4);

  // 台湾 PTT Stock（板级聚合）
  const twSum = sumMap.get("tw:TWSTOCK");
  const twVol = volMap.get("tw:TWSTOCK");
  const twPosts = getAsiaPosts("tw", "TWSTOCK", 3);
  const twBreakdown = getAsiaTwBreakdown();
  const twSeries = getAsiaTickerSeries("TWSTOCK", 8);
  const hasTw = !!twSum || twPosts.length > 0;

  // ===================== 机构级指标（对标专业舆情台）=====================
  const mFull = (m: string) => (m === "jp" ? (isZh ? "日本" : "Japan") : m === "kr" ? (isZh ? "韩国" : "Korea") : (isZh ? "台湾" : "Taiwan"));
  const mShort = (m: string) => (m === "jp" ? t.jpShort : m === "kr" ? t.krShort : t.twShort);
  const MARKET_COLOR: Record<string, string> = { jp: "#4A9EE0", kr: "#E6B450", tw: "#B07CE6" };
  const labelOf = (s: { ticker: string; market: string }) => (s.ticker === "TWSTOCK" ? nameOf("TWSTOCK") : `${nameOf(s.ticker)}·${mShort(s.market)}`);

  const summaries = [...sumMap.values()];
  const engRows = getAsiaEngagement();
  const engMap = new Map(engRows.map((e) => [`${e.market}:${e.ticker}`, e]));

  // 净情绪榜（多−空）
  const netItems = summaries.map((s) => ({ label: labelOf(s), value: Math.round(s.bull_pct - s.bear_pct) }));

  // 舆情定位气泡（净情绪 × 声量 × 互动）
  const bubble = summaries.map((s) => {
    const e = engMap.get(`${s.market}:${s.ticker}`);
    const engage = e ? e.likes + e.comments + Math.round((e.views || 0) / 20) : s.post_count;
    return { name: nameOf(s.ticker), x: Math.round(s.bull_pct - s.bear_pct), y: s.post_count, size: Math.max(engage, s.post_count, 1), color: MARKET_COLOR[s.market], market: mFull(s.market) };
  });

  // 情绪日历热力
  const heat = getAsiaSentiHeat(7);
  const heatY = heat.tickers.map((tk) => nameOf(tk));

  // 声量异动 z-score（每标的本周最反常的一天）
  const mean = (a: number[]) => a.reduce((x, y) => x + y, 0) / a.length;
  const std = (a: number[]) => { const m = mean(a); return Math.sqrt(a.reduce((x, y) => x + (y - m) ** 2, 0) / a.length); };
  const buzzByTicker = new Map<string, { day: string; vol: number }[]>();
  for (const r of dayTick) { const a = buzzByTicker.get(r.ticker) ?? []; a.push({ day: r.day, vol: r.vol }); buzzByTicker.set(r.ticker, a); }
  const buzzItems = [...buzzByTicker.entries()].map(([tk, arr]) => {
    if (arr.length < 4) return null;
    const vols = arr.map((x) => x.vol); const m = mean(vols), sd = std(vols);
    if (!sd) return null;
    let best = arr[0], bz = 0;
    for (const x of arr) { const z = (x.vol - m) / sd; if (Math.abs(z) > Math.abs(bz)) { bz = z; best = x; } }
    return { label: `${nameOf(tk)} ${dayMD(best.day)}`, value: +bz.toFixed(2) };
  }).filter((x): x is { label: string; value: number } => !!x);

  // 市场画像雷达（归一化 0..1）
  const marketAgg = (["jp", "kr", "tw"] as const).map((m) => {
    const cells = summaries.filter((s) => s.market === m);
    const posts = cells.reduce((a, s) => a + s.post_count, 0);
    const moodW = posts ? cells.reduce((a, s) => a + s.mood_score * s.post_count, 0) / posts : 0;
    const bullSum = cells.reduce((a, s) => a + s.bull_pct, 0), bearSum = cells.reduce((a, s) => a + s.bear_pct, 0);
    const bullRatio = bullSum + bearSum ? bullSum / (bullSum + bearSum) : 0.5;
    const em = engRows.filter((e) => e.market === m);
    const n = em.reduce((a, e) => a + e.n, 0);
    const engPer = n ? (em.reduce((a, e) => a + e.likes + e.comments, 0)) / n : 0;
    const qv = em.map((e) => e.quality).filter((x): x is number => x != null);
    const quality = qv.length ? qv.reduce((a, b) => a + b, 0) / qv.length : 0;
    return { m, posts, mood: moodW, bullRatio, engPer, quality };
  }).filter((a) => a.posts > 0);
  const maxPosts = Math.max(1, ...marketAgg.map((a) => a.posts));
  const maxEng = Math.max(0.01, ...marketAgg.map((a) => a.engPer));
  const radarInd = [
    { name: t.radarSentiment, max: 1 }, { name: t.radarVolume, max: 1 }, { name: t.radarEngage, max: 1 },
    { name: t.radarQuality, max: 1 }, { name: t.radarBull, max: 1 },
  ];
  const radarSeries = marketAgg.map((a) => ({
    name: mFull(a.m), color: MARKET_COLOR[a.m],
    value: [+((a.mood + 1) / 2).toFixed(2), +(a.posts / maxPosts).toFixed(2), +(a.engPer / maxEng).toFixed(2), +a.quality.toFixed(2), +a.bullRatio.toFixed(2)],
  }));

  // 认证持仓 vs 大众（韩国）
  const verSplit = getAsiaVerifiedSplit();
  const verCats = verSplit.map((v) => mFull(v.market));
  const verSeries = [
    { name: t.verifiedHolder, color: "#24B47E", data: verSplit.map((v) => v.verAvg) },
    { name: t.verifiedCrowd, color: "#7a8a96", data: verSplit.map((v) => v.crowdAvg) },
  ];
  const verDiff = verSplit.length && verSplit[0].verAvg != null && verSplit[0].crowdAvg != null
    ? +(verSplit[0].verAvg - verSplit[0].crowdAvg).toFixed(3) : null;

  // 认可度 & 争议（赞/踩，日韩）
  const approvalRows = engRows
    .filter((e) => e.dislikes > 0 && e.approval != null)
    .map((e) => ({ key: `${e.market}:${e.ticker}`, name: labelOf(e), approval: e.approval as number, likes: e.likes, dislikes: e.dislikes, engaged: e.likes + e.dislikes }))
    .sort((a, b) => b.engaged - a.engaged).slice(0, 8);

  // 日本散户自评（强买→强卖）
  const RATING = [
    { jp: "強く買いたい", zh: "强烈看多", en: "Strong Buy", color: "#1c8c5a" },
    { jp: "買いたい", zh: "看多", en: "Buy", color: "#24B47E" },
    { jp: "様子見", zh: "观望", en: "Hold", color: "#8A8A93" },
    { jp: "売りたい", zh: "看空", en: "Sell", color: "#F0556E" },
    { jp: "強く売りたい", zh: "强烈看空", en: "Strong Sell", color: "#c4384f" },
  ];
  const srMap = new Map(getAsiaJpSelfRating().map((s) => [s.label, s.n]));
  const srItems = RATING.map((r) => ({ ...r, n: srMap.get(r.jp) ?? 0 }));
  const srTotal = srItems.reduce((a, b) => a + b.n, 0);

  // 主题情绪倾向
  const themeStance = getAsiaThemeStance();

  return (
    <div className="space-y-5">
      <PageHeader
        eyebrow={t.eyebrow}
        eyebrowColor="text-amber"
        title={t.title}
        subtitle={t.subtitle}
        right={
          hasData ? (
            <div className="flex gap-2 flex-wrap">
              <HeaderStat label={t.statPosts} value={fmtInt(meta.posts)} />
              <HeaderStat label={t.statAnalyzed} value={fmtInt(meta.analyzed)} />
              <HeaderStat label={t.statTickers} value={String(meta.tickers)} />
              <HeaderStat label={t.weekOf} value={range} />
            </div>
          ) : undefined
        }
      />

      <div className="flex flex-wrap items-center gap-x-5 gap-y-2 text-[11px] text-neutral-500">
        <span className="inline-flex items-center gap-1.5"><Badge kind="live" t={t} /> {t.legendLive}</span>
        <span className="text-neutral-600">· {t.disclaimer}</span>
      </div>

      {!hasData ? (
        <Panel className="p-10 text-center text-neutral-500 text-sm">{t.empty}</Panel>
      ) : (
        <>
          {/* 维度 1：情绪矩阵 */}
          <Panel className="p-5">
            <SectionTitle title={t.matrix} hint={t.matrixHint} accent="reddit" icon="layers" />
            <div className="overflow-x-auto">
              <table className="w-full min-w-[520px] border-separate border-spacing-1.5">
                <thead>
                  <tr className="text-[11px] text-neutral-500">
                    <th className="text-left font-medium pl-1 w-28"> </th>
                    <th className="font-medium">🇯🇵 {t.jpShort}</th>
                    <th className="font-medium">🇰🇷 {t.krShort}</th>
                    <th className="font-medium">{t.combined}</th>
                  </tr>
                </thead>
                <tbody>
                  {perTicker.map(({ tk, jp, kr, combined }) => (
                    <tr key={tk.key}>
                      <td className="pl-1">
                        <div className="font-display font-bold text-cream text-sm leading-tight">{nameOf(tk.key)}</div>
                        <div className="font-mono text-[10px] text-neutral-600">{tk.key}</div>
                      </td>
                      <MoodTd s={jp} t={t} />
                      <MoodTd s={kr} t={t} />
                      <td>
                        <div className={`rounded-lg ring-1 ring-inset px-2 py-1.5 text-center ${moodCellClass(combined)}`}>
                          <div className="font-mono font-bold text-sm tabular">{fmtMood(combined)}</div>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Panel>

          {/* 台湾 · PTT Stock 板级脉搏（综合板，单独成区）*/}
          {hasTw && (
            <Panel className="p-5">
              <div className="flex items-center justify-between gap-3 mb-3 flex-wrap">
                <div className="flex items-center gap-2">
                  <span className="text-lg">🇹🇼</span>
                  <h2 className="font-display font-bold text-cream text-[15px]">{t.twTitle}</h2>
                  <span className="text-[11px] text-neutral-600">{t.twHint}</span>
                </div>
                {twSum && (
                  <div className="flex items-center gap-3 text-xs">
                    <span className={`font-semibold ${sentTextClass(twSum.mood_score)}`}>
                      {t[MOOD_KEY[twSum.mood_label] ?? "moodNeutral"]} {fmtMood(twSum.mood_score)}
                    </span>
                    {twVol && <span className="text-neutral-500 tabular">📝 {fmtInt(twVol.n)} · 👍 {fmtCompact(twVol.likes)}</span>}
                  </div>
                )}
              </div>
              <div className="grid lg:grid-cols-2 gap-4 items-start">
                {/* 左：综述 + 多空 + 代表帖 */}
                <div className="space-y-3">
                  {twSum && (
                    <>
                      <div className="h-1.5 w-full rounded-full overflow-hidden flex bg-white/[.05]">
                        <div className="bg-bull" style={{ width: `${twSum.bull_pct}%` }} />
                        <div className="bg-neutral-600" style={{ width: `${twSum.neutral_pct}%` }} />
                        <div className="bg-bear" style={{ width: `${twSum.bear_pct}%` }} />
                      </div>
                      {(isZh ? twSum.overview_zh : twSum.overview_en) && (
                        <p className="text-[13px] leading-relaxed text-neutral-300">{isZh ? twSum.overview_zh : twSum.overview_en}</p>
                      )}
                      <Points summary={twSum} isZh={isZh} />
                    </>
                  )}
                  {twPosts.length > 0 && (
                    <div className="space-y-2 pt-0.5">
                      <div className="text-[10px] uppercase tracking-wider text-neutral-500">{t.twPosts}</div>
                      {twPosts.map((p) => <PostRow key={p.id} p={p} t={t} isZh={isZh} lang={lang} />)}
                    </div>
                  )}
                </div>
                {/* 右：每日趋势 + 类别 + 热门标的 */}
                <div className="space-y-3">
                  <div>
                    <div className="text-[11px] text-neutral-500 mb-1 px-1">{t.twTrend}</div>
                    <AsiaComboChart data={twSeries} height={190} />
                  </div>
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <div className="text-[10px] uppercase tracking-wider text-neutral-500 mb-1.5">{t.twCategories}</div>
                      <div className="space-y-1">
                        {twBreakdown.categories.slice(0, 6).map((c) => (
                          <div key={c.label} className="flex items-center justify-between text-[11px]">
                            <span className="text-neutral-300">{c.label}</span>
                            <span className="font-mono text-neutral-500 tabular">{c.n}</span>
                          </div>
                        ))}
                      </div>
                    </div>
                    <div>
                      <div className="text-[10px] uppercase tracking-wider text-neutral-500 mb-1.5">{t.twStocks}</div>
                      <div className="flex flex-wrap gap-1">
                        {twBreakdown.stocks.map((s) => (
                          <span key={s.name} className="inline-flex items-center gap-1 text-[11px] px-1.5 py-0.5 rounded bg-white/[.05] text-neutral-300 ring-1 ring-inset ring-white/10">
                            {s.name}<span className="text-neutral-600 tabular">{s.n}</span>
                          </span>
                        ))}
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </Panel>
          )}

          {/* 机构级指标（对标 Swaggy Stocks / Buzzberg / E*TRADE）*/}
          <div>
            <SectionTitle title={t.proTitle} hint={t.proHint} accent="gold" icon="trophy" />

            {/* 净情绪榜 + 舆情定位气泡 */}
            <div className="grid lg:grid-cols-2 gap-4 items-start">
              <Panel className="p-5">
                <SectionTitle title={t.netTitle} hint={t.netHint} accent="bull" icon="trend" />
                <AsiaDivergingBars items={netItems} height={Math.max(180, netItems.length * 30)} />
              </Panel>
              <Panel className="p-5">
                <SectionTitle title={t.bubbleTitle} hint={t.bubbleHint} accent="reddit" icon="layers" />
                <AsiaBubble points={bubble} xName={t.bubbleX} yName={t.bubbleY} height={320} />
              </Panel>
            </div>

            {/* 情绪日历热力 */}
            {heat.cells.length > 0 && (
              <Panel className="p-5 mt-4">
                <SectionTitle title={t.heatTitle} hint={t.heatHint} accent="amber" icon="pulse" />
                <AsiaHeatmap x={heat.days} y={heatY} cells={heat.cells} height={70 + heatY.length * 30} />
              </Panel>
            )}

            {/* 声量异动 z-score + 市场画像雷达 */}
            <div className="grid lg:grid-cols-2 gap-4 items-start mt-4">
              {buzzItems.length > 0 && (
                <Panel className="p-5">
                  <SectionTitle title={t.buzzTitle} hint={t.buzzHint} accent="reddit" icon="flame" />
                  <AsiaDivergingBars items={buzzItems} unit="σ" height={Math.max(160, buzzItems.length * 34)} />
                </Panel>
              )}
              {radarSeries.length > 0 && (
                <Panel className="p-5">
                  <SectionTitle title={t.radarTitle} hint={t.radarHint} accent="gold" icon="layers" />
                  <AsiaRadar indicators={radarInd} series={radarSeries} height={320} />
                </Panel>
              )}
            </div>

            {/* 认证持仓 vs 大众 + 认可度 & 争议 */}
            <div className="grid lg:grid-cols-2 gap-4 items-start mt-4">
              {verSplit.length > 0 && (
                <Panel className="p-5">
                  <SectionTitle title={t.verifiedTitle} hint={t.verifiedHint} accent="bull" icon="trophy" />
                  <AsiaPairedBars categories={verCats} series={verSeries} sentiment height={210} />
                  {verDiff != null && (
                    <div className="mt-2 text-[11px] text-center">
                      <span className={verDiff >= 0 ? "text-bull" : "text-bear"}>
                        {verDiff >= 0 ? t.verifiedMore : t.verifiedLess} ({verDiff > 0 ? "+" : ""}{verDiff})
                      </span>
                      <span className="text-neutral-600"> · n={verSplit[0].verN}</span>
                    </div>
                  )}
                </Panel>
              )}
              {approvalRows.length > 0 && (
                <Panel className="p-5">
                  <SectionTitle title={t.approvalTitle} hint={t.approvalHint} accent="amber" icon="pulse" />
                  <div className="space-y-2.5">
                    {approvalRows.map((r) => <ApprovalRow key={r.key} r={r} t={t} />)}
                  </div>
                </Panel>
              )}
            </div>

            {/* 日本自评 + 主题情绪倾向 */}
            <div className="grid lg:grid-cols-2 gap-4 items-start mt-4">
              {srTotal > 0 && (
                <Panel className="p-5">
                  <SectionTitle title={t.selfRateTitle} hint={t.selfRateHint} accent="reddit" icon="doc" />
                  <div className="h-4 w-full rounded-full overflow-hidden flex bg-white/[.04] mt-1">
                    {srItems.filter((s) => s.n > 0).map((s) => (
                      <div key={s.jp} style={{ width: `${(s.n / srTotal) * 100}%`, background: s.color }} title={`${isZh ? s.zh : s.en} · ${s.n}`} />
                    ))}
                  </div>
                  <div className="mt-3 grid grid-cols-2 sm:grid-cols-3 gap-x-3 gap-y-1.5">
                    {srItems.map((s) => (
                      <div key={s.jp} className="flex items-center gap-1.5 text-[11px]">
                        <i className="w-2.5 h-2.5 rounded-sm inline-block shrink-0" style={{ background: s.color }} />
                        <span className="text-neutral-300">{isZh ? s.zh : s.en}</span>
                        <span className="ml-auto font-mono text-neutral-500 tabular">{s.n}</span>
                      </div>
                    ))}
                  </div>
                </Panel>
              )}
              {themeStance.length > 0 && (
                <Panel className="p-5">
                  <SectionTitle title={t.themeStanceTitle} hint={t.themeStanceHint} accent="neutral" icon="doc" />
                  <div className="flex flex-wrap gap-1.5">
                    {themeStance.map((th) => {
                      const net = th.bull - th.bear;
                      const cls = net > 0 ? "bg-bull/10 text-bull ring-bull/20" : net < 0 ? "bg-bear/10 text-bear ring-bear/20" : "bg-white/[.05] text-neutral-300 ring-white/10";
                      return (
                        <span key={th.theme} className={`inline-flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-md ring-1 ring-inset ${cls}`}>
                          {net > 0 ? "▲" : net < 0 ? "▼" : "·"} {th.theme}<span className="opacity-60 tabular">{th.n}</span>
                        </span>
                      );
                    })}
                  </div>
                </Panel>
              )}
            </div>

            <p className="mt-2 text-[10px] text-neutral-600 px-1">{t.proNote}</p>
          </div>

          {/* 维度 2+3：声量榜 + 每日声量 */}
          <div className="grid lg:grid-cols-2 gap-4 items-start">
            <Panel className="p-5">
              <SectionTitle title={t.volumeTitle} hint={t.volumeHint} accent="gold" icon="trophy" />
              <div className="space-y-2.5">
                {[...perTicker].sort((a, b) => b.vol - a.vol).map(({ tk, vol, volJp, volKr }) => (
                  <div key={tk.key} className="grid grid-cols-[70px_1fr_44px] items-center gap-2.5">
                    <span className="font-mono text-xs text-cream truncate">{nameOf(tk.key)}</span>
                    <div className="h-3.5 w-full rounded-full bg-white/[.05] overflow-hidden flex" title={`日 ${volJp} · 韩 ${volKr}`}>
                      <div className="h-full bg-reddit/80" style={{ width: `${(volJp / maxVol) * 100}%` }} />
                      <div className="h-full bg-amber/80" style={{ width: `${(volKr / maxVol) * 100}%` }} />
                    </div>
                    <span className="font-mono text-xs text-neutral-400 tabular text-right">{fmtInt(vol)}</span>
                  </div>
                ))}
              </div>
              <div className="mt-3 flex gap-4 text-[10px] text-neutral-500">
                <span className="inline-flex items-center gap-1"><i className="w-2.5 h-2.5 rounded-sm bg-reddit/80 inline-block" /> {t.jp}</span>
                <span className="inline-flex items-center gap-1"><i className="w-2.5 h-2.5 rounded-sm bg-amber/80 inline-block" /> {t.kr}</span>
              </div>
            </Panel>

            <Panel className="p-5">
              <SectionTitle title={t.dailyTitle} hint={t.dailyHint} accent="amber" icon="pulse" />
              <div className="flex items-end justify-between gap-1.5 h-32 px-1">
                {daily.map((d) => (
                  <div key={d.day} className="flex-1 flex flex-col items-center gap-1 group">
                    <div className="w-full flex flex-col justify-end h-24" title={`${dayMD(d.day)} · 日 ${d.jp} / 韩 ${d.kr}`}>
                      <div className="w-full rounded-t-sm bg-amber/70" style={{ height: `${(d.kr / maxDaily) * 100}%` }} />
                      <div className="w-full bg-reddit/70" style={{ height: `${(d.jp / maxDaily) * 100}%` }} />
                    </div>
                    <span className="text-[9px] text-neutral-600 tabular">{dayMD(d.day)}</span>
                    <span className="text-[9px] text-neutral-500 tabular">{d.total}</span>
                  </div>
                ))}
              </div>
            </Panel>
          </div>

          {/* 维度 4+5：跨市场分歧 + 主题 */}
          <div className="grid lg:grid-cols-2 gap-4 items-start">
            <Panel className="p-5">
              <SectionTitle title={t.divergenceTitle} hint={t.divergenceHint} accent="bull" icon="trend" />
              <div className="space-y-2.5">
                {[...perTicker].filter((p) => p.divergence !== null)
                  .sort((a, b) => (b.divergence ?? 0) - (a.divergence ?? 0))
                  .map(({ tk, jp, kr, divergence }) => (
                    <div key={tk.key} className="grid grid-cols-[64px_1fr_1fr_46px] items-center gap-2 text-xs">
                      <span className="font-mono text-cream truncate">{nameOf(tk.key)}</span>
                      <div className="flex items-center gap-1.5">
                        <span className="text-[10px] text-neutral-600 w-4">{t.jpShort}</span>
                        <span className={`font-mono tabular ${sentTextClass(jp!.mood_score)}`}>{fmtMood(jp!.mood_score)}</span>
                      </div>
                      <div className="flex items-center gap-1.5">
                        <span className="text-[10px] text-neutral-600 w-4">{t.krShort}</span>
                        <span className={`font-mono tabular ${sentTextClass(kr!.mood_score)}`}>{fmtMood(kr!.mood_score)}</span>
                      </div>
                      <span className={`font-mono tabular text-right font-bold ${(divergence ?? 0) >= 0.5 ? "text-amber" : "text-neutral-500"}`}>
                        Δ{(divergence ?? 0).toFixed(2)}
                      </span>
                    </div>
                  ))}
              </div>
            </Panel>

            <Panel className="p-5">
              <SectionTitle title={t.themesTitle} accent="neutral" icon="doc" />
              <div className="flex flex-wrap gap-1.5">
                {topThemes.length ? topThemes.map(([th, n]) => (
                  <span key={th} className="inline-flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-md bg-gold/10 text-gold ring-1 ring-inset ring-gold/15">
                    {th}<span className="text-gold/60 tabular">{n}</span>
                  </span>
                )) : <span className="text-xs text-neutral-600">—</span>}
              </div>
            </Panel>
          </div>

          {/* 维度 6：趋势 · 变化（每日声量/情绪 + 异动榜）*/}
          <div>
            <SectionTitle title={t.trendsTitle} accent="amber" icon="pulse" />
            <div className="grid lg:grid-cols-2 gap-4 items-start">
              <Panel className="p-4">
                <div className="text-[11px] text-neutral-500 mb-1 px-1">{t.trendVolTitle}</div>
                <AsiaMultiLine x={trendDays} series={volSeries} height={210} />
              </Panel>
              <Panel className="p-4">
                <div className="text-[11px] text-neutral-500 mb-1 px-1">{t.trendSentiTitle}</div>
                <AsiaMultiLine x={trendDays} series={sentiSeries} height={210} sentiment />
              </Panel>
            </div>
            {/* 异动榜 */}
            <Panel className="p-5 mt-4">
              <SectionTitle title={t.moversTitle} hint={t.moversHint} accent="reddit" icon="flame" />
              <div className="grid sm:grid-cols-2 gap-x-8 gap-y-2">
                <div>
                  <div className="text-[11px] font-semibold text-amber mb-1.5">{t.moversVol}</div>
                  {movers.volume.map((m, i) => (
                    <MoverRow key={`v${i}`} name={nameOf(m.ticker)} day={dayMD(m.day)}
                      text={`${m.prev} → ${m.cur}`} delta={`${m.delta > 0 ? "+" : ""}${m.delta}`} up={m.delta > 0} />
                  ))}
                </div>
                <div>
                  <div className="text-[11px] font-semibold text-amber mb-1.5">{t.moversSenti}</div>
                  {movers.sentiment.map((m, i) => (
                    <MoverRow key={`s${i}`} name={nameOf(m.ticker)} day={dayMD(m.day)}
                      text={`${fmtMood(m.prev)} → ${fmtMood(m.cur)}`} delta={`${m.delta > 0 ? "+" : ""}${m.delta.toFixed(2)}`} up={m.delta > 0} />
                  ))}
                </div>
              </div>
            </Panel>
          </div>

          {/* 维度 7：价格 × 情绪 × 声量 指数图（每标的）*/}
          <div>
            <SectionTitle title={t.comboTitle} hint={t.comboHint} accent="gold" icon="trend" />
            <div className="grid lg:grid-cols-2 gap-4">
              {TICKERS.map((tk) => {
                const series = combo.get(tk.key) ?? [];
                return (
                  <Panel key={tk.key} className="p-4">
                    <div className="flex items-baseline gap-2 mb-1 px-1">
                      <span className="font-display font-bold text-cream text-sm">{nameOf(tk.key)}</span>
                      <span className="font-mono text-[10px] text-neutral-600">{tk.key}</span>
                    </div>
                    {series.some((p) => p.price != null) || series.length ? (
                      <AsiaComboChart data={series} height={230} />
                    ) : (
                      <div className="py-8 text-center text-xs text-neutral-600">{t.noBoardTitle}</div>
                    )}
                  </Panel>
                );
              })}
            </div>
            <p className="mt-2 text-[10px] text-neutral-600 px-1">{t.priceNote}</p>
          </div>

          {/* 维度 8：个股详情 · 日 vs 韩 */}
          <div>
            <SectionTitle title={t.detailsTitle} accent="reddit" icon="layers" />
            <div className="space-y-4">
              {TICKERS.map((tk) => (
                <Panel key={tk.key} className="p-4">
                  <div className="flex items-baseline gap-2 mb-3">
                    <span className="font-display font-bold text-cream text-[15px]">{nameOf(tk.key)}</span>
                    <span className="font-mono text-xs text-neutral-500">{tk.key}</span>
                  </div>
                  <div className="grid md:grid-cols-2 gap-4">
                    {MARKETS.map((m) => (
                      <MarketCol
                        key={m}
                        market={m}
                        summary={sumMap.get(`${m}:${tk.key}`)}
                        vol={volMap.get(`${m}:${tk.key}`)}
                        posts={postMap.get(`${m}:${tk.key}`) ?? []}
                        t={t}
                        isZh={isZh}
                        lang={lang}
                      />
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

function MoodTd({ s, t }: { s?: AsiaSummary; t: any }) {
  if (!s) return <td><div className="rounded-lg ring-1 ring-inset ring-white/10 bg-white/[.02] px-2 py-1.5 text-center text-neutral-600 text-xs">—</div></td>;
  return (
    <td>
      <div className={`rounded-lg ring-1 ring-inset px-2 py-1.5 text-center ${moodCellClass(s.mood_score)}`} title={`多${s.bull_pct}% / 空${s.bear_pct}%`}>
        <div className="font-mono font-bold text-sm tabular leading-none">{fmtMood(s.mood_score)}</div>
        <div className="text-[9px] opacity-80 mt-0.5">{t[MOOD_KEY[s.mood_label] ?? "moodNeutral"]}</div>
      </div>
    </td>
  );
}

// 单市场列（详情区）
function MarketCol({
  market, summary, vol, posts, t, isZh, lang,
}: {
  market: string; summary?: AsiaSummary; vol?: AsiaVolumeRow; posts: AsiaPostRow[]; t: any; isZh: boolean; lang: Locale;
}) {
  const flag = market === "jp" ? "🇯🇵" : "🇰🇷";
  const name = market === "jp" ? t.jp : t.kr;
  const isEmpty = !summary && posts.length === 0;

  return (
    <div className="rounded-lg bg-white/[.015] ring-1 ring-inset ring-white/[.05] p-3 space-y-2.5">
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold text-neutral-300">{flag} {name}</span>
        {summary && (
          <span className={`text-[11px] font-semibold ${sentTextClass(summary.mood_score)}`}>
            {t[MOOD_KEY[summary.mood_label] ?? "moodNeutral"]} {fmtMood(summary.mood_score)}
          </span>
        )}
      </div>

      {isEmpty ? (
        <div className="py-4 text-center text-xs text-neutral-600">{t.noBoardTitle}</div>
      ) : (
        <>
          {summary && (
            <div className="h-1.5 w-full rounded-full overflow-hidden flex bg-white/[.05]">
              <div className="bg-bull" style={{ width: `${summary.bull_pct}%` }} />
              <div className="bg-neutral-600" style={{ width: `${summary.neutral_pct}%` }} />
              <div className="bg-bear" style={{ width: `${summary.bear_pct}%` }} />
            </div>
          )}

          {/* 互动维度统计 */}
          {vol && (
            <div className="flex flex-wrap gap-x-3 gap-y-1 text-[10px] text-neutral-500 tabular">
              <span>📝 {fmtInt(vol.n)}</span>
              <span>👍 {fmtCompact(vol.likes)}</span>
              <span>💬 {fmtCompact(vol.comments)}</span>
              <span>👁 {fmtCompact(vol.views)}</span>
              {vol.verified > 0 && <span className="text-bull/70">✓ {vol.verified}</span>}
              {vol.withImage > 0 && <span>📷 {vol.withImage}</span>}
            </div>
          )}

          {summary && (isZh ? summary.overview_zh : summary.overview_en) && (
            <p className="text-[12px] leading-relaxed text-neutral-300">{isZh ? summary.overview_zh : summary.overview_en}</p>
          )}

          {summary && <Points summary={summary} isZh={isZh} />}

          {posts.length > 0 && (
            <div className="space-y-2 pt-0.5">
              {posts.map((p) => <PostRow key={p.id} p={p} t={t} isZh={isZh} lang={lang} />)}
            </div>
          )}

          {summary && summary.top_themes.length > 0 && (
            <div className="flex flex-wrap gap-1 pt-0.5">
              {summary.top_themes.slice(0, 3).map((th) => <ThemeTag key={th}>{th}</ThemeTag>)}
            </div>
          )}
        </>
      )}
    </div>
  );
}

function Points({ summary, isZh }: { summary: AsiaSummary; isZh: boolean }) {
  const bull = (isZh ? summary.top_bull_zh : summary.top_bull_en).slice(0, 2);
  const bear = (isZh ? summary.top_bear_zh : summary.top_bear_en).slice(0, 2);
  if (!bull.length && !bear.length) return null;
  return (
    <div className="space-y-1">
      {bull.map((b, i) => (
        <div key={`u${i}`} className="flex gap-1.5 text-[11px] text-neutral-400"><span className="text-bull mt-0.5 shrink-0">▲</span><span className="leading-snug">{b}</span></div>
      ))}
      {bear.map((b, i) => (
        <div key={`d${i}`} className="flex gap-1.5 text-[11px] text-neutral-400"><span className="text-bear mt-0.5 shrink-0">▼</span><span className="leading-snug">{b}</span></div>
      ))}
    </div>
  );
}

function PostRow({ p, t, isZh, lang }: { p: AsiaPostRow; t: any; isZh: boolean; lang: Locale }) {
  const text = (isZh ? p.tldr_zh : p.tldr_en) || p.body.slice(0, 80);
  return (
    <div className="rounded-md bg-white/[.02] ring-1 ring-inset ring-white/[.05] px-2.5 py-1.5">
      <div className="flex items-center gap-1.5 mb-1 flex-wrap">
        <SentPill stance={p.stance} score={p.sentiment} />
        {p.label && <span className="text-[10px] px-1.5 py-0.5 rounded bg-white/[.05] text-neutral-400 ring-1 ring-inset ring-white/10">{p.label}</span>}
        {p.verified > 0 && <span className="text-[9px] px-1 py-0.5 rounded bg-bull/12 text-bull/90" title="持股认证">✓</span>}
        <span className="ml-auto text-[10px] text-neutral-600 tabular whitespace-nowrap">{p.created ? timeAgo(p.created, lang) : ""}</span>
      </div>
      <p className="text-[12px] leading-snug text-neutral-300 line-clamp-2">{text}</p>
      <div className="flex items-center gap-2.5 mt-1 text-[10px] text-neutral-600 tabular">
        <span>👍{fmtCompact(p.likes)}</span>
        {p.dislikes > 0 && <span>👎{fmtCompact(p.dislikes)}</span>}
        {p.comments > 0 && <span>💬{fmtCompact(p.comments)}</span>}
        {p.views > 0 && <span>👁{fmtCompact(p.views)}</span>}
        {p.images > 0 && <span>📷{p.images}</span>}
        {p.origin !== "sample" && p.url && (
          <a href={p.url} target="_blank" rel="noopener noreferrer nofollow" className="ml-auto text-neutral-500 hover:text-amber transition">{t.viewSource} ↗</a>
        )}
      </div>
    </div>
  );
}

function MoverRow({ name, day, text, delta, up }: { name: string; day: string; text: string; delta: string; up: boolean }) {
  return (
    <div className="flex items-center gap-2 py-1 text-xs border-b border-line/40 last:border-0">
      <span className="font-mono text-cream w-16 truncate">{name}</span>
      <span className="text-[10px] text-neutral-600 w-10 tabular">{day}</span>
      <span className="text-neutral-500 tabular flex-1">{text}</span>
      <span className={`font-mono font-bold tabular ${up ? "text-bull" : "text-bear"}`}>{delta}</span>
    </div>
  );
}

function ApprovalRow({ r, t }: { r: { name: string; approval: number; likes: number; dislikes: number; engaged: number }; t: any }) {
  const pct = Math.round(r.approval * 100);
  const divisive = r.approval >= 0.4 && r.approval <= 0.6;
  return (
    <div className="grid grid-cols-[90px_1fr_72px] items-center gap-2.5">
      <span className="font-mono text-xs text-cream truncate">{r.name}</span>
      <div className="h-3.5 w-full rounded-full bg-white/[.05] overflow-hidden flex" title={`👍 ${r.likes} / 👎 ${r.dislikes}`}>
        <div className="h-full bg-bull/80" style={{ width: `${pct}%` }} />
        <div className="h-full bg-bear/70" style={{ width: `${100 - pct}%` }} />
      </div>
      <div className="flex items-center justify-end gap-1">
        {divisive && <span className="text-[8px] font-bold uppercase tracking-wide px-1 py-0.5 rounded bg-amber/15 text-amber">{t.controversyTag}</span>}
        <span className="font-mono text-xs text-neutral-400 tabular">{pct}%</span>
      </div>
    </div>
  );
}

function Badge({ kind, t }: { kind: "live" | "sample"; t: any }) {
  const cls = kind === "sample" ? "bg-amber/12 text-amber ring-amber/25" : "bg-bull/12 text-bull ring-bull/25";
  return <span className={`text-[9px] font-bold uppercase tracking-wider px-1.5 py-0.5 rounded ring-1 ring-inset ${cls}`}>{kind === "sample" ? t.sampleTag : t.liveTag}</span>;
}
