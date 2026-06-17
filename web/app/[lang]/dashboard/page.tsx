import { LocaleLink } from "@/components/i18n/LocaleLink";
import { Panel, SectionTitle, Eyebrow, MiniBar, ScoreNum } from "@/components/ui";
import { FeedGrid } from "@/components/FeedGrid";
import { NarrativeCard } from "@/components/NarrativeCard";
import { TodaysAlpha } from "@/components/TodaysAlpha";
import { ViewTracker } from "@/components/ViewTracker";
import { IconFlame, IconWaves } from "@/components/icons";
import { fmtInt, sentTextClass } from "@/lib/format";
import { getDictionary, isLocale, defaultLocale, type Locale } from "@/lib/i18n";
import {
  getMarketMood, getMindshare, getTrending, getNarratives, getFeed, getMeta, getTodaysAlpha,
  getSentimentLeaders,
} from "@/lib/queries";

export default function Overview({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const t = getDictionary(lang).dashboard;

  const meta = getMeta();
  const mood = getMarketMood();
  const alpha = getTodaysAlpha(3);
  const mind = getMindshare(12);
  const leaders = getSentimentLeaders("us", 5);
  const spikes = getTrending(8);
  const narratives = getNarratives(6);
  const feed = getFeed({ limit: 24 });
  const maxShare = mind[0]?.mindshare || 1;
  const maxHeat = Math.max(1, ...narratives.map((n) => n.heat));

  return (
    <div className="space-y-4">
      {/* 首页头牌：今日 Reddit Alpha（置顶、Reddit 橙主题、视觉最强）。
          数据可信度「依据模块」已移至顶部 banner（Topbar）。
          ViewTracker：测该位「可见曝光」(MRC 50%×1s)，用于真实 eCPM 估算。 */}
      <ViewTracker slot="dash_hero">
        <TodaysAlpha alphas={alpha} />
      </ViewTracker>

      {/* Masthead */}
      <div className="flex flex-wrap items-center justify-between gap-x-6 gap-y-4 pb-4 border-b border-line">
        <div>
          <div className="flex items-center gap-1.5 text-reddit">
            <IconWaves className="w-5 h-3.5" />
            <Eyebrow color="text-reddit">{t.eyebrow}</Eyebrow>
          </div>
          <h1 className="mt-1.5 font-display font-extrabold text-cream text-[26px] leading-none tracking-tight">
            {t.heading}
          </h1>
        </div>
        <div className="flex items-stretch rounded-lg ring-1 ring-inset ring-white/[.06] bg-white/[.012] divide-x divide-line max-w-full overflow-x-auto [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
          {mood && (
            <KPI label={t.kpiMood} value={mood.label} sub={`${mood.mood_score > 0 ? "+" : ""}${mood.mood_score.toFixed(2)}`} tone={sentTextClass(mood.mood_score)} />
          )}
          <KPI label={t.kpiTickers} value={fmtInt(meta.tickers)} />
          <KPI label={t.kpiPosts} value={fmtInt(meta.posts)} />
          <KPI label={t.kpiMentions} value={fmtInt(meta.mentions)} />
        </div>
      </div>

      {/* 第一行：热度榜（条形=声量、颜色=情绪）+ 异动&风向（合并卡） */}
      <div className="grid lg:grid-cols-2 gap-4 items-start">
        {/* 热度榜：不显示具体数字——条形长度=相对声量，颜色=多空情绪，一眼看排名与方向 */}
        <Panel className="p-5">
          <SectionTitle title={t.topTitle} accent="gold" icon="trophy" />
          <div className="space-y-0.5">
            {mind.map((r, i) => (
              <LocaleLink
                key={r.ticker}
                href={`/ticker/${r.ticker}`}
                title={`${r.name} · ${r.mindshare.toFixed(1)}% · ${r.sentiment > 0 ? "+" : ""}${r.sentiment.toFixed(2)}`}
                className="grid grid-cols-[22px_64px_1fr] items-center gap-3 px-2 py-2 rounded-lg hover:bg-white/[.03] transition group"
              >
                <span className="flex justify-end">
                  {i < 3 ? (
                    <span className={`grid place-items-center w-5 h-5 rounded-full text-[10px] font-extrabold metal-fill ${i === 0 ? "m-gold" : i === 1 ? "m-silver" : "m-bronze"}`}>{i + 1}</span>
                  ) : (
                    <span className="w-1.5 h-1.5 rounded-full bg-neutral-700" />
                  )}
                </span>
                <span className="font-mono font-semibold text-cream group-hover:text-amber transition">{r.ticker}</span>
                <MiniBar pct={(r.mindshare / maxShare) * 100} color={sentBar(r.sentiment)} />
              </LocaleLink>
            ))}
          </div>
        </Panel>

        {/* 异动 & 多空风向标：合并为一张卡，两段（条形+颜色，无数字） */}
        <Panel className="p-5 space-y-5">
          {/* 异动飙升：条形=飙升幅度(z)，颜色=情绪，🔥=触发 spike */}
          <div>
            <SectionTitle title={t.spikeTitle} accent="amber" icon="flame" />
            <div className="space-y-0.5">
              {spikes.slice(0, 6).map((x) => (
                <LocaleLink
                  key={x.ticker}
                  href={`/ticker/${x.ticker}`}
                  className="flex items-center justify-between gap-2 px-2 py-1.5 rounded-lg hover:bg-white/[.03] transition group"
                >
                  <div className="flex items-center gap-2 min-w-0">
                    {x.spike ? <IconFlame className="w-3.5 h-3.5 text-amber shrink-0" /> : <span className="w-3.5 shrink-0" />}
                    <span className="font-mono font-semibold text-cream group-hover:text-amber transition truncate">{x.ticker}</span>
                    <span className="text-xs text-neutral-600 tabular shrink-0">{x.mentions}{t.mentionsSuffix}</span>
                  </div>
                  <div className="flex items-center gap-3 shrink-0">
                    <span className="font-mono text-xs text-amber tabular">z {x.zscore > 0 ? "+" : ""}{x.zscore.toFixed(1)}</span>
                    <span className="text-xs"><ScoreNum score={x.sentiment} /></span>
                  </div>
                </LocaleLink>
              ))}
            </div>
          </div>

          {/* 多空风向标：两列，条形长度=情绪强度，绿=最看多 / 红=最看空 */}
          <div className="border-t border-line pt-4">
            <SectionTitle title={t.leadersTitle} hint={t.leadersHint} accent="bull" icon="trend" />
            {leaders.bullish.length || leaders.bearish.length ? (
              <div className="grid grid-cols-2 gap-x-5 gap-y-2">
                {([
                  { label: t.leadersBull, dot: "bg-bull", color: "text-bull", rows: leaders.bullish },
                  { label: t.leadersBear, dot: "bg-bear", color: "text-bear", rows: leaders.bearish },
                ] as const).map((col) => (
                  <div key={col.label}>
                    <div className={`flex items-center gap-1.5 mb-2 text-[15px] font-bold ${col.color}`}>
                      <span className={`w-2 h-2 rounded-full ${col.dot}`} />
                      {col.label}
                    </div>
                    <div className="space-y-0.5">
                      {col.rows.length ? (
                        col.rows.slice(0, 5).map((r) => (
                          <LocaleLink
                            key={r.ticker}
                            href={`/ticker/${r.ticker}`}
                            className="flex items-center justify-between gap-2 px-1.5 py-1 rounded-md hover:bg-white/[.03] transition group"
                          >
                            <span className="font-mono text-sm font-semibold text-cream group-hover:text-amber transition truncate">{r.ticker}</span>
                            <span className="text-xs"><ScoreNum score={r.sentiment} /></span>
                          </LocaleLink>
                        ))
                      ) : (
                        <div className="px-1 py-1 text-xs text-neutral-600">{t.leadersEmpty}</div>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <div className="text-sm text-neutral-600 py-4 text-center">{t.leadersEmpty}</div>
            )}
          </div>
        </Panel>
      </div>

      {/* 第二行：主导叙事（整宽） */}
      <div>
        <SectionTitle title={t.narrativesTitle} accent="reddit" icon="layers" />
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {narratives.map((n) => (
            <NarrativeCard key={n.id} n={n} maxHeat={maxHeat} />
          ))}
        </div>
      </div>

      {/* 高质量 DD 帖（getFeed 已按 quality 排序）。ViewTracker：信息流中部广告位的可见曝光。 */}
      <ViewTracker slot="dash_feed">
        <SectionTitle title={t.ddTitle} accent="neutral" icon="doc" />
        <FeedGrid posts={feed} initial={6} />
      </ViewTracker>
    </div>
  );
}

function KPI({ label, value, sub, tone = "text-cream" }: { label: string; value: string; sub?: string; tone?: string }) {
  return (
    <div className="px-4 py-2 shrink-0 whitespace-nowrap">
      <div className="text-[10px] uppercase tracking-wider text-neutral-500">{label}</div>
      <div className="mt-0.5 flex items-baseline gap-1.5">
        <span className={`font-display font-bold text-lg tabular leading-none ${tone}`}>{value}</span>
        {sub && <span className={`font-mono text-xs tabular ${tone}`}>{sub}</span>}
      </div>
    </div>
  );
}

// 情绪→条形颜色：绿=看多 / 红=看空 / 灰=中性。用颜色直观表达多空方向（替代数字）。
function sentBar(score: number): string {
  return score > 0.15 ? "bg-bull" : score < -0.15 ? "bg-bear" : "bg-neutral-500";
}
