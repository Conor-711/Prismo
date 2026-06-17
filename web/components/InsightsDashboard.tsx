"use client";

import { useCallback, useEffect, useState } from "react";
import { LocaleLink } from "./i18n/LocaleLink";
import { useLocale } from "./i18n/LocaleProvider";
import { useAuth } from "./auth/AuthProvider";
import { isAdminEmail } from "@/lib/admin";
import { analyticsRpc, isTrackingDisabled, setTrackingDisabled } from "@/lib/analytics";
import { fmtInt, fmtCompact } from "@/lib/format";

interface Overview {
  events: number; page_views: number; visitors: number; sessions: number;
  views_today: number; visitors_today: number;
}
interface Daily { day: string; views: number; visitors: number }
interface Pair { label: string; value: number }
interface Recent { ts: string; event_type: string; path: string | null; lang: string | null; ticker: string | null }
interface Engagement {
  sessions: number; visitors: number;
  avg_session_seconds: number; avg_visitor_seconds: number;
  avg_pages_per_session: number; avg_pages_per_visitor: number;
  avg_clicks_per_visitor: number; avg_clicks_per_session: number;
  bounce_rate: number;
}
interface EngagedPath { path: string; views: number; visitors: number; avg_seconds: number; clicks: number; avg_scroll: number }
type KN = { k: string; n: number };
interface Audience {
  devices: KN[]; browsers: KN[]; os: KN[]; languages: KN[]; timezones: KN[];
  new_visitors: number; returning_visitors: number; visitors: number; sessions: number;
}
interface Channels { channels: KN[]; campaigns: KN[] }
interface Funnel { landing: number; dashboard: number; ticker: number; post: number; share: number }
interface SearchTerm { term: string; n: number; found: number }
interface Retention { max: number; cohorts: { date: string; size: number; pct: (number | null)[] }[]; curve: { d: number; pct: number | null }[] }
interface Inventory { days: number; impressions: number; visitors: number; sessions: number; viewable?: number; view_slots?: KN[] }
interface Pwa { standalone_visitors: number; standalone_sessions: number; installs: number }
interface WeekRow { week: string; new: number; returning: number; total: number }
interface Returning { weeks: WeekRow[]; frequency: KN[]; wau: number; mau: number; stickiness: number }
interface Data {
  overview: Overview; engagement: Engagement | null; engagedPaths: EngagedPath[];
  audience: Audience | null; channels: Channels | null; funnel: Funnel | null;
  hourly: { hour: number; n: number }[]; searchTerms: SearchTerm[];
  retention: Retention | null; inventory: Inventory | null; pwa: Pwa | null;
  returning: Returning | null; retentionWeekly: Retention | null;
  daily: Daily[]; topPaths: Pair[];
  events: Pair[]; tickers: Pair[]; langs: Pair[];
  sources: Pair[]; shares: Pair[]; recent: Recent[];
}

// KN[]（{k,n}）→ BarList 用的 {label,value}
function kn(arr?: KN[] | null): Pair[] {
  return (arr ?? []).map((r) => ({ label: r.k, value: Number(r.n) }));
}

export function InsightsDashboard() {
  const { dict } = useLocale();
  const t = dict.insights;
  const { user, loading: authLoading, configured, signOut } = useAuth();
  const admin = isAdminEmail(user?.email);
  const [data, setData] = useState<Data | null>(null);
  const [fetching, setFetching] = useState(false);
  const [failed, setFailed] = useState(false);
  const [dnt, setDnt] = useState(false); // 本设备是否「排除我的访问」
  useEffect(() => setDnt(isTrackingDisabled()), []);

  const load = useCallback(async () => {
    setFetching(true);
    setFailed(false);
    const [overview, engagement, engagedPaths, audience, channels, funnel, hourly, searchTerms, retention, inventory, pwa, returning, retentionWeekly, daily, topPaths, events, tickers, langs, sources, shares, recent] = await Promise.all([
      analyticsRpc<Overview>("analytics_overview"),
      analyticsRpc<Engagement>("analytics_engagement", { p_days: 30 }),
      analyticsRpc<EngagedPath[]>("analytics_top_paths_engaged", { p_limit: 8, p_days: 30 }),
      analyticsRpc<Audience>("analytics_audience", { p_days: 30 }),
      analyticsRpc<Channels>("analytics_channels", { p_days: 30 }),
      analyticsRpc<Funnel>("analytics_funnel", { p_days: 30 }),
      analyticsRpc<{ hour: number; n: number }[]>("analytics_hourly", { p_days: 30 }),
      analyticsRpc<SearchTerm[]>("analytics_search_terms", { p_limit: 12, p_days: 30 }),
      analyticsRpc<Retention>("analytics_retention", { p_days: 21, p_max: 7 }),
      analyticsRpc<Inventory>("analytics_inventory", { p_days: 30 }),
      analyticsRpc<Pwa>("analytics_pwa", { p_days: 30 }),
      analyticsRpc<Returning>("analytics_returning", { p_weeks: 8 }),
      analyticsRpc<Retention>("analytics_retention_weekly", { p_weeks: 8, p_max: 6 }),
      analyticsRpc<Daily[]>("analytics_daily", { p_days: 14 }),
      analyticsRpc<{ path: string; views: number }[]>("analytics_top_paths", { p_limit: 8, p_days: 30 }),
      analyticsRpc<{ event_type: string; n: number }[]>("analytics_event_breakdown", { p_days: 30 }),
      analyticsRpc<{ ticker: string; n: number }[]>("analytics_top_tickers", { p_limit: 8, p_days: 30 }),
      analyticsRpc<{ lang: string; n: number }[]>("analytics_lang_split", { p_days: 30 }),
      analyticsRpc<{ source: string; n: number }[]>("analytics_traffic_sources", { p_limit: 8, p_days: 30 }),
      analyticsRpc<{ platform: string; n: number }[]>("analytics_shares", { p_days: 30 }),
      analyticsRpc<Recent[]>("analytics_recent", { p_limit: 25 }),
    ]);
    if (!overview) {
      setFailed(true);
      setData(null);
    } else {
      setData({
        overview,
        engagement: engagement ?? null,
        engagedPaths: engagedPaths ?? [],
        audience: audience ?? null,
        channels: channels ?? null,
        funnel: funnel ?? null,
        hourly: hourly ?? [],
        searchTerms: searchTerms ?? [],
        retention: retention ?? null,
        inventory: inventory ?? null,
        pwa: pwa ?? null,
        returning: returning ?? null,
        retentionWeekly: retentionWeekly ?? null,
        daily: daily ?? [],
        topPaths: (topPaths ?? []).map((r) => ({ label: r.path, value: Number(r.views) })),
        events: (events ?? []).map((r) => ({ label: r.event_type, value: Number(r.n) })),
        tickers: (tickers ?? []).map((r) => ({ label: r.ticker, value: Number(r.n) })),
        langs: (langs ?? []).map((r) => ({ label: r.lang, value: Number(r.n) })),
        sources: (sources ?? []).map((r) => ({ label: r.source, value: Number(r.n) })),
        shares: (shares ?? []).map((r) => ({ label: r.platform, value: Number(r.n) })),
        recent: recent ?? [],
      });
    }
    setFetching(false);
  }, []);

  useEffect(() => {
    if (user && admin) void load();
  }, [user, admin, load]);

  // ---- 门槛态 ----
  if (!configured) return <Notice>{t.needConfig}</Notice>;
  if (authLoading) return <Notice>{t.loading}</Notice>;
  if (!user)
    return (
      <Notice>
        {t.needLogin}{" "}
        <LocaleLink href="/login" className="text-reddit font-semibold hover:underline">
          {t.loginCta} →
        </LocaleLink>
      </Notice>
    );
  // 已登录但非管理员：拒绝访问（数据仅管理员可见；后端 RPC 也会再校验一次）
  if (!admin)
    return (
      <Notice tone="warn">
        {t.notAdmin}{" "}
        <button onClick={() => void signOut()} className="text-reddit font-semibold hover:underline">
          {t.switchAccount} →
        </button>
      </Notice>
    );

  return (
    <div className="space-y-5">
      <div className="flex items-end justify-between gap-3">
        <div>
          <div className="eyebrow text-reddit">{t.eyebrow}</div>
          <h1 className="mt-1 font-display font-extrabold text-cream tracking-tight text-[26px] leading-tight">{t.title}</h1>
          <p className="mt-1 text-sm text-neutral-500">{t.subtitle}</p>
        </div>
        <div className="flex items-center gap-2 shrink-0">
          {/* 排除我自己的访问：本设备开关（登录为管理员时已自动开启） */}
          <button
            onClick={() => { const v = !dnt; setTrackingDisabled(v); setDnt(v); }}
            title={t.dntHint}
            className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-[13px] font-semibold ring-1 ring-inset transition ${
              dnt ? "text-bull bg-bull/10 ring-bull/30" : "text-neutral-400 bg-white/[.04] ring-line hover:text-cream hover:bg-white/[.07]"
            }`}
          >
            <span className={`w-1.5 h-1.5 rounded-full ${dnt ? "bg-bull" : "bg-neutral-500"}`} />
            {dnt ? t.dntOn : t.dntOff}
          </button>
          <button
            onClick={() => void load()}
            disabled={fetching}
            className="inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-[13px] font-semibold text-neutral-300 bg-white/[.04] ring-1 ring-inset ring-line hover:text-cream hover:bg-white/[.07] transition disabled:opacity-50"
          >
            <RefreshIcon spinning={fetching} /> {t.refresh}
          </button>
        </div>
      </div>

      {failed && <Notice tone="warn">{t.needMigration}</Notice>}
      {!failed && !data && <Notice>{t.loading}</Notice>}

      {data && (
        <>
          {/* —— 触达（受众规模：访客 / 浏览 / 会话）—— */}
          <SectionLabel hint={t.secReachHint}>{t.secReach}</SectionLabel>
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
            <Kpi label={t.kpiVisitors} value={data.overview.visitors} sub={`${t.todayPrefix}+${fmtInt(data.overview.visitors_today)}`} />
            <Kpi label={t.kpiViews} value={data.overview.page_views} sub={`${t.todayPrefix}+${fmtInt(data.overview.views_today)}`} />
            <Kpi label={t.kpiSessions} value={data.overview.sessions} />
            <Kpi label={t.kpiEvents} value={data.overview.events} />
          </div>

          {/* —— 参与度（人均停留 / 点击 / 页数 / 跳出；产品迭代 + 广告主可信度）—— */}
          {data.engagement && (
            <>
              <SectionLabel hint={t.secEngageHint}>{t.secEngage}</SectionLabel>
              {/* 「人均停留」已移除：其口径含会话时间跨度(span_ms)，易被空闲/挂着高估，不对外展示。
                  页面级「停留」(纯活跃时间)仍保留在「最爱页面」表里。 */}
              <div className="grid grid-cols-3 gap-3">
                <Kpi accent label={t.engClicksVisitor} text={data.engagement.avg_clicks_per_visitor.toFixed(1)} sub={`${t.perSession} ${data.engagement.avg_clicks_per_session.toFixed(1)}`} />
                <Kpi label={t.engPagesVisitor} text={data.engagement.avg_pages_per_visitor.toFixed(1)} sub={`${t.perSession} ${data.engagement.avg_pages_per_session.toFixed(1)}`} />
                <Kpi label={t.engBounce} text={`${Math.round(data.engagement.bounce_rate)}%`} sub={t.bounceHint} />
              </div>
            </>
          )}

          {/* —— 获取渠道（用户从哪来）—— */}
          <SectionLabel hint={t.secAcqHint}>{t.secAcq}</SectionLabel>
          <div className="grid md:grid-cols-3 gap-4">
            <Card title={t.chanTitle}><BarList items={kn(data.channels?.channels)} empty={t.noData} unit={t.unit} /></Card>
            <Card title={t.campaignTitle}><BarList items={kn(data.channels?.campaigns)} empty={t.noData} unit={t.unit} mono /></Card>
            <Card title={t.trafficSources}><BarList items={data.sources} empty={t.noData} unit={t.unit} mono /></Card>
          </div>

          {/* —— 受众画像（他们是谁）—— */}
          {data.audience && (
            <>
              <SectionLabel hint={t.secAudienceHint}>{t.secAudience}</SectionLabel>
              <div className="grid grid-cols-3 gap-3">
                <Kpi label={t.audNew} value={data.audience.new_visitors} />
                <Kpi label={t.audReturning} value={data.audience.returning_visitors} />
                <Kpi accent label={t.audReturnRate} text={`${pct(data.audience.returning_visitors, data.audience.visitors)}%`} sub={t.audReturnHint} />
              </div>
              {/* 「把站点存下来」的可追踪信号：加到主屏/独立启动 + 安装次数（原生书签无法统计）。 */}
              {data.pwa && (
                <div className="rounded-xl ring-1 ring-inset ring-reddit/20 bg-reddit/[.05] px-4 py-2.5 text-[13px] text-neutral-300 flex flex-wrap items-center gap-x-4 gap-y-1">
                  <span className="font-semibold text-reddit">{t.pwaSavedLabel}</span>
                  <span><b className="font-mono text-cream">{fmtInt(data.pwa.standalone_visitors)}</b> {t.pwaStandalone}</span>
                  <span><b className="font-mono text-cream">{fmtInt(data.pwa.installs)}</b> {t.pwaInstalls}</span>
                  <span className="text-neutral-500 text-[11px]">{t.pwaHint}</span>
                </div>
              )}
              <div className="grid md:grid-cols-3 gap-4">
                <Card title={t.deviceTitle}><BarList items={kn(data.audience.devices)} empty={t.noData} unit={t.unit} /></Card>
                <Card title={t.browserTitle}><BarList items={kn(data.audience.browsers)} empty={t.noData} unit={t.unit} /></Card>
                <Card title={t.osTitle}><BarList items={kn(data.audience.os)} empty={t.noData} unit={t.unit} /></Card>
                <Card title={t.tzTitle}><BarList items={kn(data.audience.timezones)} empty={t.noData} unit={t.unit} mono /></Card>
                <Card title={t.langSplit}><BarList items={data.langs} empty={t.noData} unit={t.unit} /></Card>
                <Card title={t.activeHours}><HourBars data={data.hourly} hint={t.activeHoursHint} /></Card>
              </div>
            </>
          )}

          {/* —— 回访（周维度）：周回访 / 粘性 / 频次 —— */}
          {data.returning && (
            <>
              <SectionLabel hint={t.secReturningHint}>{t.secReturning}</SectionLabel>
              {(() => {
                const wk = data.returning.weeks;
                const last = wk.length ? wk[wk.length - 1] : null;
                const wau = last?.total ?? data.returning.wau;
                const ret = last?.returning ?? 0;
                const rate = last && last.total > 0 ? Math.round((last.returning / last.total) * 100) : 0;
                return (
                  <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
                    <Kpi label={t.kpiWau} value={wau} />
                    <Kpi accent label={t.kpiWeekReturn} value={ret} />
                    <Kpi accent label={t.kpiWeekReturnRate} text={`${rate}%`} sub={t.weekReturnHint} />
                    <Kpi label={t.kpiStickiness} text={`${data.returning.stickiness}%`} sub={t.stickinessHint} />
                  </div>
                );
              })()}
              <div className="grid lg:grid-cols-2 gap-4">
                <Card title={t.weeklyTrendTitle}><WeeklyVisitors rows={data.returning.weeks} t={t} /></Card>
                <Card title={t.freqTitle}>
                  <BarList items={kn(data.returning.frequency).map((p) => ({ label: `${p.label}${t.freqWeekSuffix}`, value: p.value }))} empty={t.noData} unit={t.unit} />
                </Card>
              </div>
              {data.retentionWeekly && data.retentionWeekly.cohorts.length > 0 && (
                <div className="grid lg:grid-cols-2 gap-4">
                  <Card title={t.weeklyCurveTitle}><RetentionCurve r={data.retentionWeekly} unit="W" /></Card>
                  <Card title={t.weeklyCohortTitle}><CohortTable r={data.retentionWeekly} t={t} unit="W" /></Card>
                </div>
              )}
              <p className="text-[11px] text-neutral-500 -mt-1">{t.weeklyNote}</p>
            </>
          )}

          {/* —— 留存（同期群）：新访客第 N 天还回来吗 —— */}
          {data.retention && data.retention.cohorts.length > 0 && (
            <>
              <SectionLabel hint={t.secRetentionHint}>{t.secRetention}</SectionLabel>
              <div className="grid lg:grid-cols-2 gap-4">
                <Card title={t.retCurveTitle}><RetentionCurve r={data.retention} /></Card>
                <Card title={t.retCohortTitle}><CohortTable r={data.retention} t={t} /></Card>
              </div>
              <p className="text-[11px] text-neutral-500 -mt-1">{t.retNote}</p>
            </>
          )}

          {/* —— 内容与意图（看什么、搜什么、读多深）—— */}
          <SectionLabel hint={t.secBehaviorHint}>{t.secBehavior}</SectionLabel>
          <Card title={t.topPagesEngaged}><EngagedPaths rows={data.engagedPaths} t={t} /></Card>
          <div className="grid md:grid-cols-2 gap-4">
            <Card title={t.searchTermsTitle}><SearchTerms rows={data.searchTerms} t={t} /></Card>
            <Card title={t.topTickers}><BarList items={data.tickers} empty={t.noData} unit={t.unit} mono /></Card>
          </div>

          {/* —— 转化漏斗 —— */}
          {data.funnel && (
            <>
              <SectionLabel hint={t.funnelHint}>{t.funnelTitle}</SectionLabel>
              <Card title={t.funnelTitle}><FunnelView f={data.funnel} t={t} /></Card>
            </>
          )}

          {/* 趋势 + 事件 / 分享分布 */}
          <Card title={t.trendTitle}><Trend daily={data.daily} viewsLabel={t.trendViews} /></Card>
          <div className="grid md:grid-cols-2 gap-4">
            <Card title={t.eventsTitle}><BarList items={data.events} empty={t.noData} unit={t.unit} /></Card>
            <Card title={t.sharesTitle}><BarList items={data.shares} empty={t.noData} unit={t.unit} /></Card>
          </div>

          {/* —— 广告主视角（可直接用于招商 / media kit）—— */}
          {data.engagement && (
            <>
              <SectionLabel hint={t.secAdsHint}>{t.secAds}</SectionLabel>
              <div className="rounded-2xl ring-1 ring-inset ring-reddit/25 bg-reddit/[.06] px-4 py-3.5 text-[13px] text-neutral-200 leading-relaxed space-y-1.5">
                <p>
                  <span className="font-semibold text-reddit">{t.adPitchLabel}</span>{" "}
                  {t.adPitch
                    .replace("{visitors}", fmtInt(data.engagement.visitors))
                    .replace("{pages}", data.engagement.avg_pages_per_session.toFixed(1))
                    .replace("{clicks}", data.engagement.avg_clicks_per_visitor.toFixed(1))}
                </p>
                {data.audience && (
                  <p className="text-neutral-400">
                    <span className="font-semibold text-neutral-300">{t.adComposeLabel}</span>{" "}
                    {t.adAudience
                      .replace("{device}", topLabel(data.audience.devices) || "—")
                      .replace("{ret}", `${pct(data.audience.returning_visitors, data.audience.visitors)}%`)
                      .replace("{channel}", topChannel(data.channels) || "—")}
                  </p>
                )}
              </div>
              {data.inventory && (
                <Card title={t.ecpmTitle}><EcpmView inv={data.inventory} t={t} /></Card>
              )}
            </>
          )}

          {/* 最近事件 */}
          <Card title={t.recent}><RecentTable rows={data.recent} t={t} /></Card>
        </>
      )}
    </div>
  );
}

/* ---------- 子组件 ---------- */

function Notice({ children, tone = "muted" }: { children: React.ReactNode; tone?: "muted" | "warn" }) {
  const cls = tone === "warn" ? "text-gold ring-gold/25 bg-gold/5" : "text-neutral-400 ring-line bg-white/[.02]";
  return <div className={`rounded-xl ring-1 ring-inset px-4 py-5 text-sm ${cls}`}>{children}</div>;
}

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="rounded-2xl ring-1 ring-inset ring-line bg-white/[.02] p-4 sm:p-5">
      <h2 className="font-display font-bold text-cream text-[14px] mb-3">{title}</h2>
      {children}
    </section>
  );
}

function Kpi({ label, value, text, sub, accent }: { label: string; value?: number; text?: string; sub?: string; accent?: boolean }) {
  return (
    <div className={`rounded-2xl ring-1 ring-inset p-4 ${accent ? "ring-reddit/30 bg-reddit/5" : "ring-line bg-white/[.02]"}`}>
      <div className="text-[11px] uppercase tracking-wider text-neutral-500">{label}</div>
      <div className={`mt-1.5 font-mono font-bold text-[26px] tabular leading-none ${accent ? "text-reddit" : "text-cream"}`}>
        {text ?? fmtCompact(value ?? 0)}
      </div>
      {sub && <div className="mt-1.5 text-[11px] text-bull">{sub}</div>}
    </div>
  );
}

// 秒 → 友好时长："1m 35s" / "42s"
function fmtDur(seconds: number): string {
  const s = Math.max(0, Math.round(seconds));
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  const r = s % 60;
  return r ? `${m}m ${r}s` : `${m}m`;
}

// 区块小标题
function SectionLabel({ children, hint }: { children: React.ReactNode; hint?: string }) {
  return (
    <div className="flex items-baseline gap-2 mt-1">
      <span className="w-1 h-3.5 rounded-full bg-reddit shrink-0" />
      <h2 className="font-display font-bold text-cream text-[15px] tracking-tight">{children}</h2>
      {hint && <span className="text-[11px] text-neutral-500">{hint}</span>}
    </div>
  );
}

// 最爱页面（含停留 / 独立访客 / 滚动深度 / 点击）
function EngagedPaths({ rows, t }: { rows: EngagedPath[]; t: { noData: string; colPath: string; colViews: string; colVisitors: string; colDwell: string; colClicks: string; colScroll: string } }) {
  if (!rows.length) return <p className="text-sm text-neutral-600 py-2">{t.noData}</p>;
  const max = Math.max(1, ...rows.map((r) => r.views));
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-[13px]">
        <thead>
          <tr className="text-[11px] uppercase tracking-wider text-neutral-500 text-left">
            <th className="font-medium pb-2">{t.colPath}</th>
            <th className="font-medium pb-2 text-right">{t.colViews}</th>
            <th className="font-medium pb-2 text-right hidden sm:table-cell">{t.colVisitors}</th>
            <th className="font-medium pb-2 text-right">{t.colDwell}</th>
            <th className="font-medium pb-2 text-right">{t.colScroll}</th>
            <th className="font-medium pb-2 text-right hidden sm:table-cell">{t.colClicks}</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.path} className="border-t border-line/60">
              <td className="py-2 pr-3">
                <span className="font-mono text-neutral-200 truncate inline-block max-w-[180px] align-middle" title={r.path}>{r.path}</span>
                <span className="ml-2 inline-block h-1 rounded-full bg-reddit/50 align-middle" style={{ width: `${Math.round((r.views / max) * 60)}px` }} />
              </td>
              <td className="py-2 text-right font-mono tabular text-cream">{fmtInt(r.views)}</td>
              <td className="py-2 text-right font-mono tabular text-neutral-400 hidden sm:table-cell">{fmtInt(r.visitors)}</td>
              <td className="py-2 text-right font-mono tabular text-bull">{fmtDur(r.avg_seconds)}</td>
              <td className="py-2 text-right font-mono tabular text-neutral-300">{Math.round(r.avg_scroll)}%</td>
              <td className="py-2 text-right font-mono tabular text-neutral-400 hidden sm:table-cell">{fmtInt(r.clicks)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// 百分比 + 取首位标签（回访率、广告主受众构成用）
function pct(a: number, b: number): number { return b > 0 ? Math.round((a / b) * 100) : 0; }
function topLabel(arr?: KN[] | null): string { return arr && arr.length ? arr[0].k : ""; }
function topChannel(c?: Channels | null): string {
  const list = (c?.channels ?? []).filter((x) => x.k !== "internal");
  return list.length ? list[0].k : "";
}

// 活跃时段：24 小时柱状（UTC+8）
function HourBars({ data, hint }: { data: { hour: number; n: number }[]; hint: string }) {
  const max = Math.max(1, ...data.map((d) => d.n));
  return (
    <div>
      <div className="flex items-end gap-[3px] h-20">
        {data.map((d) => (
          <div key={d.hour} className="group relative flex-1 flex flex-col justify-end items-center">
            <div
              className="w-full rounded-t bg-reddit/55 group-hover:bg-reddit transition-all"
              style={{ height: `${Math.max(2, Math.round((d.n / max) * 100))}%` }}
              title={`${d.hour}:00 · ${d.n}`}
            />
          </div>
        ))}
      </div>
      <div className="mt-1.5 flex justify-between text-[10px] text-neutral-600 font-mono">
        <span>0</span><span>6</span><span>12</span><span>18</span><span>23</span>
      </div>
      <p className="mt-1 text-[11px] text-neutral-500">{hint}</p>
    </div>
  );
}

// 站内搜索词（含命中数）
function SearchTerms({ rows, t }: { rows: SearchTerm[]; t: { noData: string; colTerm: string; colSearches: string; colFound: string } }) {
  if (!rows.length) return <p className="text-sm text-neutral-600 py-2">{t.noData}</p>;
  return (
    <table className="w-full text-[13px]">
      <thead>
        <tr className="text-[11px] uppercase tracking-wider text-neutral-500 text-left">
          <th className="font-medium pb-2">{t.colTerm}</th>
          <th className="font-medium pb-2 text-right">{t.colSearches}</th>
          <th className="font-medium pb-2 text-right">{t.colFound}</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((r) => (
          <tr key={r.term} className="border-t border-line/60">
            <td className="py-1.5 font-mono text-neutral-200 truncate max-w-[160px]" title={r.term}>{r.term}</td>
            <td className="py-1.5 text-right font-mono tabular text-cream">{fmtInt(r.n)}</td>
            <td className="py-1.5 text-right font-mono tabular text-neutral-400">{fmtInt(r.found)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

// 转化漏斗：各阶段独立访客 + 相对上一阶段转化率
function FunnelView({ f, t }: { f: Funnel; t: { stLanding: string; stDashboard: string; stTicker: string; stPost: string; stShare: string } }) {
  const stages = [
    { label: t.stLanding, v: f.landing },
    { label: t.stDashboard, v: f.dashboard },
    { label: t.stTicker, v: f.ticker },
    { label: t.stPost, v: f.post },
    { label: t.stShare, v: f.share },
  ];
  const top = Math.max(1, ...stages.map((s) => s.v));
  return (
    <ul className="space-y-2.5">
      {stages.map((s, i) => {
        const prev = i === 0 ? s.v : stages[i - 1].v;
        const conv = i === 0 ? 100 : prev > 0 ? Math.round((s.v / prev) * 100) : 0;
        return (
          <li key={s.label} className="flex items-center gap-3">
            <span className="text-[13px] text-neutral-300 w-16 shrink-0">{s.label}</span>
            <span className="flex-1 h-5 rounded-md bg-white/[.05] overflow-hidden">
              <span className="block h-full rounded-md bg-reddit/55" style={{ width: `${Math.max(3, Math.round((s.v / top) * 100))}%` }} />
            </span>
            <span className="font-mono tabular text-[13px] text-cream w-12 text-right">{fmtInt(s.v)}</span>
            <span className="font-mono tabular text-[11px] text-neutral-500 w-10 text-right">{i === 0 ? "" : `${conv}%`}</span>
          </li>
        );
      })}
    </ul>
  );
}

// 留存曲线（聚合，按已满 n 期的同期群加权）。unit="D" 日 / "W" 周。
function RetentionCurve({ r, unit = "D" }: { r: Retention; unit?: "D" | "W" }) {
  return (
    <div className="flex items-end gap-2 h-28">
      {r.curve.map((p) => (
        <div key={p.d} className="flex-1 flex flex-col items-center justify-end">
          <span className="text-[10px] font-mono text-neutral-400 mb-1">{p.pct == null ? "·" : `${p.pct}%`}</span>
          <div
            className="w-full rounded-t bg-reddit/60"
            style={{ height: `${p.pct == null ? 2 : Math.max(2, p.pct)}%` }}
            title={`${unit}${p.d} · ${p.pct ?? "—"}%`}
          />
          <span className="mt-1 text-[10px] font-mono text-neutral-500">{unit}{p.d}</span>
        </div>
      ))}
    </div>
  );
}

// 同期群三角（行=获取日期/周，列=N0..Nmax，单元格=留存%热力）。unit="D" 日 / "W" 周。
function CohortTable({ r, t, unit = "D" }: { r: Retention; t: { retColCohort: string; retColSize: string; noData: string }; unit?: "D" | "W" }) {
  if (!r.cohorts.length) return <p className="text-sm text-neutral-600 py-2">{t.noData}</p>;
  const cols = r.max + 1;
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-[12px]">
        <thead>
          <tr className="text-[10px] uppercase tracking-wider text-neutral-500 text-left">
            <th className="font-medium pb-2 pr-2">{t.retColCohort}</th>
            <th className="font-medium pb-2 pr-2 text-right">{t.retColSize}</th>
            {Array.from({ length: cols }).map((_, i) => (
              <th key={i} className="font-medium pb-2 px-1 text-center font-mono">{unit}{i}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {r.cohorts.map((c) => (
            <tr key={c.date} className="border-t border-line/50">
              <td className="py-1 pr-2 font-mono text-neutral-300 whitespace-nowrap">{c.date.slice(5)}</td>
              <td className="py-1 pr-2 text-right font-mono tabular text-neutral-400">{c.size}</td>
              {Array.from({ length: cols }).map((_, i) => {
                const v = c.pct[i];
                return (
                  <td key={i} className="py-1 px-0.5 text-center">
                    {v == null ? (
                      <span className="text-neutral-700">·</span>
                    ) : (
                      <span
                        className="inline-block min-w-[26px] rounded px-1 py-0.5 text-[11px] font-mono tabular text-neutral-50"
                        style={{ backgroundColor: `rgba(255,69,0,${(0.1 + (v / 100) * 0.6).toFixed(3)})` }}
                      >
                        {v}
                      </span>
                    )}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// 美元紧凑格式
function fmtUsd(n: number): string {
  const v = Math.round(n);
  if (v >= 1000) return `$${(v / 1000).toFixed(v >= 10000 ? 0 : 1)}k`;
  return `$${v}`;
}

// 广告位 eCPM 估算：按月广告展示 × 各情景 eCPM × 填充率
function EcpmView({
  inv,
  t,
}: {
  inv: Inventory;
  t: {
    ecpmImpr: string; ecpmViewableImpr: string; ecpmPerMonth: string; ecpmColTier: string; ecpmColCpm: string; ecpmColRev: string;
    ecpmLow: string; ecpmMid: string; ecpmHigh: string; ecpmAssume: string; ecpmBasisReal: string;
  };
}) {
  const SLOTS = 2;
  const FILL = 0.7;
  const proj = inv.days > 0 ? 30 / inv.days : 1; // 投影到「月」
  // 有真实可见曝光(ad_view) → 用它做基数；否则回退「页面浏览 × 广告位」估算。
  const hasViewable = (inv.viewable ?? 0) > 0;
  const adImpr = hasViewable ? (inv.viewable ?? 0) * proj : inv.impressions * proj * SLOTS;
  const tiers = [
    { label: t.ecpmLow, cpm: 6 },
    { label: t.ecpmMid, cpm: 12 },
    { label: t.ecpmHigh, cpm: 22 },
  ];
  return (
    <div className="space-y-3">
      <div className="flex items-baseline gap-2">
        <span className="text-[11px] uppercase tracking-wider text-neutral-500">{hasViewable ? t.ecpmViewableImpr : t.ecpmImpr}</span>
        <span className="font-mono font-bold text-cream text-[18px] tabular">{fmtInt(Math.round(adImpr))}</span>
        <span className="text-[11px] text-neutral-500">/ {t.ecpmPerMonth}</span>
      </div>
      <table className="w-full text-[13px]">
        <thead>
          <tr className="text-[11px] uppercase tracking-wider text-neutral-500 text-left">
            <th className="font-medium pb-2">{t.ecpmColTier}</th>
            <th className="font-medium pb-2 text-right">{t.ecpmColCpm}</th>
            <th className="font-medium pb-2 text-right">{t.ecpmColRev}</th>
          </tr>
        </thead>
        <tbody>
          {tiers.map((ti) => (
            <tr key={ti.label} className="border-t border-line/60">
              <td className="py-1.5 text-neutral-300">{ti.label}</td>
              <td className="py-1.5 text-right font-mono tabular text-neutral-400">${ti.cpm.toFixed(2)}</td>
              <td className="py-1.5 text-right font-mono tabular text-bull">{fmtUsd((adImpr / 1000) * ti.cpm * FILL)}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="text-[11px] text-neutral-500">
        {hasViewable
          ? t.ecpmBasisReal.replace("{fill}", String(Math.round(FILL * 100)))
          : t.ecpmAssume.replace("{slots}", String(SLOTS)).replace("{fill}", String(Math.round(FILL * 100)))}
      </p>
    </div>
  );
}

// 每周活跃访客：新(浅) 与 回访(深) 堆叠柱
function WeeklyVisitors({ rows, t }: { rows: WeekRow[]; t: { audNew: string; audReturning: string; noData: string } }) {
  if (!rows.length) return <p className="text-sm text-neutral-600 py-2">{t.noData}</p>;
  const max = Math.max(1, ...rows.map((r) => r.total));
  return (
    <div>
      <div className="flex items-end gap-1.5 h-32">
        {rows.map((r) => (
          <div
            key={r.week}
            className="group relative flex-1 flex flex-col justify-end"
            title={`${r.week.slice(5)} · ${t.audNew} ${r.new} / ${t.audReturning} ${r.returning}`}
          >
            <div className="w-full rounded-t bg-reddit transition-all" style={{ height: `${Math.round((r.returning / max) * 100)}%` }} />
            <div className="w-full bg-reddit/30 transition-all" style={{ height: `${Math.round((r.new / max) * 100)}%` }} />
          </div>
        ))}
      </div>
      <div className="mt-1.5 flex justify-between text-[10px] text-neutral-600 font-mono">
        <span>{rows[0]?.week.slice(5)}</span>
        <span>{rows[rows.length - 1]?.week.slice(5)}</span>
      </div>
      <div className="mt-2 flex items-center gap-4 text-[11px] text-neutral-400">
        <span className="inline-flex items-center gap-1.5"><i className="w-2.5 h-2.5 rounded-sm bg-reddit/30" />{t.audNew}</span>
        <span className="inline-flex items-center gap-1.5"><i className="w-2.5 h-2.5 rounded-sm bg-reddit" />{t.audReturning}</span>
      </div>
    </div>
  );
}

function Trend({ daily, viewsLabel }: { daily: { day: string; views: number }[]; viewsLabel: string }) {
  const max = Math.max(1, ...daily.map((d) => d.views));
  return (
    <div>
      <div className="flex items-end gap-1.5 h-32">
        {daily.map((d) => (
          <div key={d.day} className="group relative flex-1 flex flex-col justify-end items-center">
            <div
              className="w-full rounded-t bg-reddit/70 group-hover:bg-reddit transition-all"
              style={{ height: `${Math.max(2, Math.round((d.views / max) * 100))}%` }}
              title={`${d.day} · ${d.views} ${viewsLabel}`}
            />
          </div>
        ))}
      </div>
      <div className="mt-1.5 flex justify-between text-[10px] text-neutral-600 font-mono">
        <span>{daily[0]?.day.slice(5)}</span>
        <span>{daily[daily.length - 1]?.day.slice(5)}</span>
      </div>
    </div>
  );
}

function BarList({ items, empty, unit, mono }: { items: { label: string; value: number }[]; empty: string; unit: string; mono?: boolean }) {
  if (!items.length) return <p className="text-sm text-neutral-600 py-2">{empty}</p>;
  const max = Math.max(1, ...items.map((i) => i.value));
  return (
    <ul className="space-y-2">
      {items.map((it) => (
        <li key={it.label} className="flex items-center gap-3">
          <span className={`text-[13px] text-neutral-300 truncate w-40 shrink-0 ${mono ? "font-mono" : ""}`} title={it.label}>
            {it.label}
          </span>
          <span className="flex-1 h-2 rounded-full bg-white/[.05] overflow-hidden">
            <span className="block h-full rounded-full bg-reddit/60" style={{ width: `${Math.round((it.value / max) * 100)}%` }} />
          </span>
          <span className="font-mono tabular text-[13px] text-neutral-400 shrink-0 w-14 text-right">
            {fmtInt(it.value)}
            {unit}
          </span>
        </li>
      ))}
    </ul>
  );
}

function RecentTable({ rows, t }: { rows: Recent[]; t: { noData: string; colTime: string; colEvent: string; colPath: string } }) {
  if (!rows.length) return <p className="text-sm text-neutral-600 py-2">{t.noData}</p>;
  return (
    <div className="overflow-x-auto -mx-1">
      <table className="w-full text-[13px]">
        <thead>
          <tr className="text-[11px] uppercase tracking-wider text-neutral-600 text-left">
            <th className="font-medium px-1 pb-2">{t.colTime}</th>
            <th className="font-medium px-1 pb-2">{t.colEvent}</th>
            <th className="font-medium px-1 pb-2">{t.colPath}</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={i} className="border-t border-line/70">
              <td className="px-1 py-1.5 font-mono text-neutral-500 whitespace-nowrap">{fmtTs(r.ts)}</td>
              <td className="px-1 py-1.5">
                <span className="inline-block px-1.5 py-0.5 rounded bg-white/[.05] text-neutral-300 font-mono text-[11px]">{r.event_type}</span>
              </td>
              <td className="px-1 py-1.5 font-mono text-neutral-400 truncate max-w-[220px]">
                {r.ticker ? `${r.path ?? ""} · ${r.ticker}` : r.path ?? ""}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function fmtTs(ts: string): string {
  try {
    const d = new Date(ts);
    return `${String(d.getMonth() + 1).padStart(2, "0")}/${String(d.getDate()).padStart(2, "0")} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
  } catch {
    return ts;
  }
}

function RefreshIcon({ spinning }: { spinning: boolean }) {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" className={spinning ? "animate-spin" : ""} aria-hidden>
      <path d="M21 12a9 9 0 1 1-2.64-6.36M21 3v6h-6" />
    </svg>
  );
}
