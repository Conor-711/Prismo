import type { Metadata } from "next";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { SentScore, Consensus, StanceBar, PriceTag } from "@/components/prismo/Bits";
import { TickerLogo } from "@/components/prismo/TickerLogo";
import { AsiaDivergingBars } from "@/components/asia/AsiaCharts";
import { Gauge, Donut } from "@/components/prismo/DetailCharts";
import { CounterThesis } from "@/components/prismo/CounterThesis";
import {
  Module, Counter, Counters, Delta, VsBaselineBar, TransmissionFlow,
  TypeBadge, Countdown, StageBadge, bi, flag,
} from "@/components/prismo/DetailBits";
import { getGrTickerSymbols, getGrTickerDetail, getGrQuote } from "@/lib/globalQueries";
import { getTickerMock } from "@/lib/mockDetail";
import { regionLabel, regionSource, regionColor } from "@/lib/regions";
import { tickerExchange, TICKER_UNIVERSE } from "@/lib/tickerMeta";
import { fmtCompact } from "@/lib/format";
import { isLocale, defaultLocale, type Locale } from "@/lib/i18n";

export const dynamicParams = false;
export function generateStaticParams() {
  // 有 gr 数据用真实标的；为空（云端快照未含 gr_*）回退到固定全集，避免 output:export 因空数组报错。
  const syms = getGrTickerSymbols();
  return (syms.length ? syms : TICKER_UNIVERSE).map((symbol) => ({ symbol }));
}
export function generateMetadata({ params }: { params: { lang: string; symbol: string } }): Metadata {
  const zh = params.lang === "zh";
  return { title: `${params.symbol} · ${zh ? "标的详情" : "Ticker"} · Prismo` };
}

export default function TickerDetail({ params }: { params: { lang: string; symbol: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  const sym = params.symbol.toUpperCase();
  // gr 数据缺失时（如云端快照未含 gr_*）用占位行：静态导出不崩，页面优雅降级（详情模块为 mock，照常渲染）。
  const ticker = getGrTickerDetail(params.symbol).ticker ?? {
    ticker: sym, name_en: sym, name_zh: sym,
    regions_present: 0, total_posts: 0, avg_sentiment: 0,
    consensus: "sparse", spread: 0, divergent_region: "",
  };

  const name = zh ? ticker.name_zh || ticker.name_en : ticker.name_en || ticker.name_zh;
  const quote = getGrQuote(ticker.ticker);
  const m = getTickerMock(ticker.ticker);
  const maxPosts = Math.max(1, ...m.regionViews.map((v) => v.posts));
  const topDim = [...m.anomaly.dims].sort((a, b) => b.sigma - a.sigma)[0];

  return (
    <div className="space-y-5">
      <LocaleLink href="/tickers" className="inline-flex items-center gap-1 text-xs text-neutral-500 hover:text-reddit transition">
        ← {zh ? "标的总览" : "All tickers"}
      </LocaleLink>

      {/* 页头 · 标的汇总 */}
      <div className="flex flex-wrap items-center justify-between gap-4 pb-4 border-b border-line">
        <div className="flex items-center gap-3.5 min-w-0">
          <TickerLogo ticker={ticker.ticker} size={52} />
          <div className="min-w-0">
            <h1 className="font-display font-extrabold text-cream text-2xl sm:text-3xl tracking-tight leading-none truncate">{name}</h1>
            <div className="mt-1.5 flex flex-wrap items-center gap-2 text-sm">
              <span className="font-mono font-semibold text-neutral-300">{ticker.ticker}</span>
              {tickerExchange(ticker.ticker) && <span className="text-neutral-600">· {tickerExchange(ticker.ticker)}</span>}
              <Consensus value={ticker.consensus} lang={lang} />
              <StageBadge stage={m.risk.stage} lang={lang} />
            </div>
          </div>
        </div>
        {quote && (
          <div className="shrink-0">
            <PriceTag price={quote.price} change={quote.price - quote.prev_close} changePct={quote.change_pct} />
            {quote.asof && <div className="mt-1 text-[10px] text-neutral-600 text-right">{zh ? "截至 " : "As of "}{quote.asof}</div>}
          </div>
        )}
      </div>

      {/* 大数字 KPI 行 */}
      <Counters>
        <Counter label={zh ? "平均情绪" : "Sentiment"} value={(ticker.avg_sentiment > 0 ? "+" : "") + ticker.avg_sentiment.toFixed(2)} sub={zh ? "五区加权" : "5-region"} tone={ticker.avg_sentiment >= 0 ? "text-bull" : "text-bear"} />
        <Counter label={zh ? "风险温度" : "Risk temp"} value={String(m.risk.temp)} sub={bi(m.risk.stage, lang)} tone={m.risk.temp > 66 ? "text-bear" : m.risk.temp > 40 ? "text-amber" : "text-bull"} />
        <Counter label={zh ? "多空比" : "Bull/bear"} value={`${m.bullBear.bullPct}%`} sub={zh ? "看多" : "bull"} tone={m.bullBear.bullPct >= 50 ? "text-bull" : "text-bear"} />
        <Counter label={zh ? "共识强度" : "Consensus"} value={String(m.bullBear.consensus)} sub="0–100" />
        <Counter label={zh ? "最强异动" : "Top anomaly"} value={`${topDim.sigma}σ`} sub={`${bi(topDim.label, lang)} ${topDim.direction === "up" ? "↑" : "↓"}`} tone={topDim.sigma >= 4 ? "text-bear" : topDim.sigma >= 2.5 ? "text-amber" : "text-cream"} />
        <Counter label={zh ? "讨论帖" : "Posts"} value={fmtCompact(ticker.total_posts)} sub={`${ticker.regions_present}/5 ${zh ? "区" : "rgn"}`} />
      </Counters>

      {/* 异动监测 */}
      <Module title={zh ? "异动监测" : "Anomaly monitor"} icon="flame" accent="reddit" hint={zh ? "各维度偏离常态基线 · σ（绿=升 / 红=降）" : "deviation from baseline · σ (green up / red down)"}>
        <div className="grid lg:grid-cols-[1fr_320px] gap-6 items-center">
          <AsiaDivergingBars height={208} unit="σ" items={m.anomaly.dims.map((d) => ({ label: bi(d.label, lang), value: d.direction === "up" ? d.sigma : -d.sigma }))} />
          <div className="lg:border-l lg:border-line lg:pl-6">
            <div className="text-[11px] uppercase tracking-wider text-neutral-500 mb-1.5">{zh ? "归因" : "Attribution"}</div>
            <p className="text-[14px] text-cream leading-relaxed">{bi(m.anomaly.attribution, lang)}</p>
            <div className="mt-3 flex flex-wrap items-center gap-x-2 gap-y-1 text-[11px]">
              <span className="px-1.5 py-0.5 rounded bg-reddit/15 text-reddit ring-1 ring-inset ring-reddit/30 text-[10px]">{zh ? "新话题" : "NEW"}</span>
              <span className="text-cream font-medium text-[12.5px]">{bi(m.anomaly.newTopic.topic, lang)}</span>
              <span className="text-bull font-mono">+{m.anomaly.newTopic.growth}%</span>
            </div>
            <div className="mt-4">
              <div className="text-[10px] uppercase tracking-wider text-neutral-500 mb-1.5">{zh ? "异动地区分布" : "Region split"}</div>
              <div className="flex h-2.5 rounded-full overflow-hidden ring-1 ring-inset ring-line">
                {m.anomaly.regionContrib.map((c) => <span key={c.region} style={{ width: `${c.pct}%`, background: regionColor(c.region) }} title={`${regionLabel(c.region, lang)} ${c.pct}%`} />)}
              </div>
              <div className="mt-1.5 flex flex-wrap gap-x-3 gap-y-0.5 text-[10px] text-neutral-500">
                {m.anomaly.regionContrib.slice(0, 3).map((c) => <span key={c.region}>{flag(c.region)} {c.pct}%</span>)}
              </div>
            </div>
          </div>
        </div>
      </Module>

      {/* 跨区域视角（大表）*/}
      <Module title={zh ? "跨区域视角" : "Cross-region view"} icon="layers" accent="bull" hint={zh ? "同一只票在五地散户社区的对比" : "this ticker across five communities"} flush>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-[11px] uppercase tracking-wider text-neutral-500 bg-white/[.02]">
                <th className="text-left font-medium pl-5 pr-3 py-2.5">{zh ? "地区" : "Region"}</th>
                <th className="text-right font-medium px-3 py-2.5">{zh ? "讨论量" : "Volume"}</th>
                <th className="text-left font-medium px-3 py-2.5 w-32 hidden md:table-cell">vs {zh ? "常态" : "base"}</th>
                <th className="text-right font-medium px-3 py-2.5">{zh ? "情绪" : "Sent"}</th>
                <th className="text-left font-medium px-3 py-2.5 w-24 hidden md:table-cell">{zh ? "多空" : "Stance"}</th>
                <th className="text-right font-medium px-3 py-2.5">{zh ? "风险" : "Risk"}</th>
                <th className="text-right font-medium px-3 py-2.5">{zh ? "领先" : "Lead"}</th>
                <th className="text-left font-medium pl-3 pr-5 py-2.5 hidden lg:table-cell">{zh ? "核心话题" : "Top topic"}</th>
              </tr>
            </thead>
            <tbody>
              {m.regionViews.map((v) => (
                <tr key={v.region} className="border-t border-line hover:bg-white/[.03] transition">
                  <td className="pl-5 pr-3 py-3"><span className="inline-flex items-center gap-2 font-semibold text-cream"><span>{flag(v.region)}</span>{regionLabel(v.region, lang)}{v.hasUnique && <span className="text-[9px] px-1 py-0.5 rounded bg-amber/15 text-amber ring-1 ring-inset ring-amber/25">{zh ? "独有" : "uniq"}</span>}</span></td>
                  <td className="px-3 py-3 text-right text-neutral-300 tabular">{fmtCompact(v.posts)} <span className="text-reddit font-mono text-[12px]">×{v.vsBaseline}</span></td>
                  <td className="px-3 py-3 hidden md:table-cell"><VsBaselineBar value={v.posts} baseline={v.posts / v.vsBaseline} max={maxPosts} /></td>
                  <td className="px-3 py-3 text-right"><span className="inline-flex items-center gap-1.5"><SentScore score={v.sentiment} /><span className="text-[10px]"><Delta value={v.sentimentChange} /></span></span></td>
                  <td className="px-3 py-3 hidden md:table-cell"><StanceBar bull={v.bullPct} bear={v.bearPct} neutral={Math.max(0, 100 - v.bullPct - v.bearPct)} /></td>
                  <td className="px-3 py-3 text-right text-neutral-400 tabular">{v.riskAppetite}%</td>
                  <td className={`px-3 py-3 text-right tabular text-[12px] ${v.leadHours >= 0 ? "text-bull" : "text-bear"}`}>{v.leadHours >= 0 ? "+" : ""}{v.leadHours}h</td>
                  <td className="pl-3 pr-5 py-3 hidden lg:table-cell"><span className="text-[11px] text-neutral-400">{bi(v.topics[0], lang)}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Module>

      {/* 多空 & 共识 | 风险温度（2-up）*/}
      <div className="grid lg:grid-cols-2 gap-5 items-start">
        <Module title={zh ? "多空 & 共识分歧" : "Bull/bear & consensus"} icon="pulse" accent="bull">
          <div className="grid sm:grid-cols-[200px_1fr] gap-5 items-center">
            <Donut height={180} centerTop={`${m.bullBear.bullPct}%`} centerBottom={zh ? "看多" : "bull"} data={[{ name: zh ? "看多" : "Bull", value: m.bullBear.bullPct, color: "#57D7BA" }, { name: zh ? "看空" : "Bear", value: m.bullBear.bearPct, color: "#fe5555" }]} />
            <div className="space-y-2.5">
              <div className="flex items-center justify-between text-[12px]"><span className="text-neutral-500">{zh ? "分歧度" : "Divergence"}</span><span className="text-cream font-mono tabular">{m.bullBear.divergence.toFixed(2)} <Delta value={m.bullBear.divergenceChange} invert /> <span className="text-[10px] text-neutral-600">{m.bullBear.divergenceChange > 0 ? (zh ? "在裂" : "↗") : zh ? "在合" : "↘"}</span></span></div>
              <div className="flex items-center justify-between text-[12px]"><span className="text-neutral-500">{zh ? "共识强度" : "Consensus"}</span><span className="text-cream font-mono tabular">{m.bullBear.consensus}</span></div>
              <div className="flex items-center justify-between text-[12px]"><span className="text-neutral-500">{zh ? "优质作者多头" : "Quality-author bull"}</span><span className="text-bull font-mono tabular">{m.bullBear.authorBull}%</span></div>
            </div>
          </div>
          <div className="mt-4 pt-4 border-t border-line grid sm:grid-cols-2 gap-3">
            <div className="rounded-lg bg-bull/[.06] ring-1 ring-inset ring-bull/20 p-3"><div className="text-[10px] uppercase tracking-wider text-bull mb-1">{zh ? "多头主线" : "Bull thesis"}</div><p className="text-[13px] text-cream">{bi(m.bullBear.bullThesis, lang)}</p></div>
            <div className="rounded-lg bg-bear/[.06] ring-1 ring-inset ring-bear/20 p-3"><div className="text-[10px] uppercase tracking-wider text-bear mb-1">{zh ? "空头主线" : "Bear thesis"}</div><p className="text-[13px] text-cream">{bi(m.bullBear.bearThesis, lang)}</p></div>
          </div>
        </Module>

        <Module title={zh ? "风险温度 / 阶段" : "Risk temperature / stage"} icon="flame" accent="amber">
          <div className="grid sm:grid-cols-[200px_1fr] gap-5 items-center">
            <div className="text-center">
              <Gauge value={m.risk.temp} tone="risk" height={180} />
              <div className="-mt-3"><StageBadge stage={m.risk.stage} lang={lang} /></div>
            </div>
            <div className="grid grid-cols-2 gap-x-4 gap-y-3.5">
              {[
                { l: zh ? "期权占比" : "Options", v: m.risk.optionsPct, b: m.risk.optionsBase, extra: `call ${m.risk.callPct}%` },
                { l: zh ? "杠杆ETF" : "Lev. ETF", v: m.risk.leveragedPct, b: m.risk.leveragedBase },
                { l: zh ? "喊单/迷因" : "Meme", v: m.risk.memePct, b: m.risk.memeBase },
                { l: zh ? "新人涌入" : "Newcomers", v: m.risk.newcomers, b: m.risk.newcomersBase, raw: true },
              ].map((s, i) => (
                <div key={i}>
                  <div className="flex items-center justify-between"><span className="text-[10px] uppercase tracking-wider text-neutral-500">{s.l}</span>{s.extra && <span className="text-[9px] text-neutral-500">{s.extra}</span>}</div>
                  <div className="mt-0.5 font-display font-bold text-cream text-[17px] tabular">{s.raw ? s.v : s.v + "%"}</div>
                  <div className="mt-1"><VsBaselineBar value={s.v} baseline={s.b} max={s.v * 1.5} /></div>
                </div>
              ))}
            </div>
          </div>
        </Module>
      </div>

      {/* 海外信息差 */}
      <Module title={zh ? "海外信息差" : "Cross-border info gap"} icon="trend" accent="reddit" hint={zh ? "话题在各地散户社区的传导路径 · 中文区滞后" : "how topics travel across communities · CN lag"}>
        <div className="divide-y divide-line">
          {m.infoGap.map((g, i) => (
            <div key={i} className="py-4 first:pt-0 last:pb-0">
              <div className="flex flex-wrap items-center justify-between gap-2 mb-3">
                <span className="font-semibold text-cream text-[15px]">{bi(g.topic, lang)}</span>
                <div className="flex items-center gap-3 text-[11px]">
                  {g.novel && <span className="px-1.5 py-0.5 rounded bg-reddit/15 text-reddit ring-1 ring-inset ring-reddit/30 text-[10px]">{zh ? "首现" : "NOVEL"}</span>}
                  <span className="text-neutral-500">{zh ? "领先中文区 " : "lead vs CN "}<span className="text-bull font-mono">+{g.leadHours}h</span></span>
                  <span className="text-neutral-500">{zh ? "增速 " : "growth "}<span className="text-bull font-mono">+{g.growth}%</span></span>
                  {g.cnPresent ? <span className="text-neutral-500">{zh ? `雪球滞后 ${g.cnLagHours}h` : `Xueqiu +${g.cnLagHours}h`}</span> : <span className="text-bear">{zh ? "雪球未现" : "Xueqiu absent"}</span>}
                </div>
              </div>
              <TransmissionFlow path={g.path} lang={lang} />
            </div>
          ))}
        </div>
      </Module>

      {/* 地区独有叙事 | 大家在等什么（2-up）*/}
      <div className="grid lg:grid-cols-2 gap-5 items-start">
        <Module title={zh ? "地区独有叙事" : "Region-unique narratives"} icon="doc" accent="amber" hint={zh ? "仅某一区在讲的故事" : "told in only one region"}>
          <div className="divide-y divide-line">
            {m.uniqueNarratives.map((n, i) => (
              <div key={i} className="py-3.5 first:pt-0 last:pb-0">
                <div className="flex items-center justify-between gap-2">
                  <span className="inline-flex items-center gap-1.5 font-semibold text-cream text-[14px]"><span>{flag(n.region)}</span>{regionLabel(n.region, lang)}</span>
                  <div className="flex items-center gap-2 text-[11px]">
                    <span className="text-reddit font-mono">×{n.heatVsBase}</span>
                    <SentScore score={n.sentiment} className="text-[12px]" />
                    {n.isNewVar && <span className="text-[10px] px-1.5 py-0.5 rounded bg-reddit/15 text-reddit ring-1 ring-inset ring-reddit/30">{zh ? "新变量" : "NEW"}</span>}
                  </div>
                </div>
                <p className="mt-1.5 text-[13.5px] text-cream font-medium">{bi(n.topic, lang)}</p>
                <p className="mt-1 text-[12px] text-neutral-500 leading-relaxed">{bi(n.diff, lang)}</p>
                <div className="mt-1 text-[10px] text-neutral-600">{zh ? "本地背景：" : "Local: "}{bi(n.note, lang)}</div>
              </div>
            ))}
          </div>
        </Module>

        <Module title={zh ? "大家在等什么" : "What everyone's waiting for"} icon="doc" accent="bull">
          <div className="divide-y divide-line">
            {m.waiting.map((e, i) => (
              <div key={i} className="py-3.5 first:pt-0 last:pb-0">
                <div className="flex items-start justify-between gap-2">
                  <div>
                    <div className="flex items-center gap-2"><span className="font-semibold text-cream text-[14px]">{bi(e.event, lang)}</span><TypeBadge type={e.type} lang={lang} /></div>
                    <div className="mt-1 text-[11px] text-neutral-500">{zh ? "聚焦：" : "Focus: "}{bi(e.focus, lang)} · {zh ? "事件前情绪 " : "pre-event "}<SentScore score={e.preLean} className="text-[12px]" /></div>
                  </div>
                  <Countdown days={e.daysOut} lang={lang} />
                </div>
                <div className="mt-2.5 space-y-1">
                  {e.regionAttention.map((a) => (
                    <div key={a.region} className="flex items-center gap-2">
                      <span className="text-[10px] w-14 text-neutral-500 shrink-0">{flag(a.region)} {regionLabel(a.region, lang)}</span>
                      <div className="flex-1 h-1.5 rounded-full bg-white/[.06] overflow-hidden"><div className="h-full rounded-full" style={{ width: `${Math.min(100, a.pct * 2.2)}%`, background: regionColor(a.region) }} /></div>
                      <span className="text-[10px] text-neutral-600 tabular w-7 text-right">{a.pct}%</span>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </Module>
      </div>

      {/* 最强反方 */}
      <Module title={zh ? "最强反方" : "Strongest counter"} icon="flame" accent="reddit" hint={zh ? "选你的持仓方向，看最强反驳" : "pick your side, see the counter"}>
        <CounterThesis bull={{ thesis: m.counter.bull.thesis, region: m.counter.bull.region, support: m.counter.bull.support }} bear={{ thesis: m.counter.bear.thesis, region: m.counter.bear.region, support: m.counter.bear.support }} counterDiscussed={m.counter.counterDiscussed} counterStrength={m.counter.counterStrength} counterSources={m.counter.counterSources} lang={lang} />
      </Module>

      <p className="text-[11px] text-neutral-600 text-center pt-1">
        {zh ? "异动 / 信号 / 风险等模块为演示数据（mock），用于展示模块设计；接入真实管线后替换。" : "Modules use mock demo data to showcase the design; to be wired to the real pipeline."}
      </p>
    </div>
  );
}
