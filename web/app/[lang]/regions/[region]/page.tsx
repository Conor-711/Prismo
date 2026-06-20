import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { SentScore, StanceBar } from "@/components/prismo/Bits";
import { TickerLogo } from "@/components/prismo/TickerLogo";
import { AsiaRadar, AsiaDivergingBars } from "@/components/asia/AsiaCharts";
import { MiniTrend, ChangeBars } from "@/components/prismo/DetailCharts";
import { HotList } from "@/components/prismo/HotList";
import { Module, Counter, Counters, SigmaBadge, Arrow, bi, flag } from "@/components/prismo/DetailBits";
import { getGrRegionSummary } from "@/lib/globalQueries";
import { getRegionMock } from "@/lib/mockDetail";
import { REGION_ORDER, regionLabel, regionSource, regionColor, isRegion } from "@/lib/regions";
import { fmtCompact } from "@/lib/format";
import { isLocale, defaultLocale, type Locale } from "@/lib/i18n";

export const dynamicParams = false;
export function generateStaticParams() {
  return REGION_ORDER.map((region) => ({ region }));
}
export function generateMetadata({ params }: { params: { lang: string; region: string } }): Metadata {
  const zh = params.lang === "zh";
  const r = isRegion(params.region) ? regionLabel(params.region, zh ? "zh" : "en") : params.region;
  return { title: `${r} · ${zh ? "区域详情" : "Region"} · Prismo` };
}

export default function RegionDetail({ params }: { params: { lang: string; region: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  const region = params.region;
  if (!isRegion(region)) notFound();

  const summary = getGrRegionSummary().find((s) => s.region === region);
  const m = getRegionMock(region);

  return (
    <div className="space-y-5">
      <LocaleLink href="/regions" className="inline-flex items-center gap-1 text-xs text-neutral-500 hover:text-reddit transition">
        ← {zh ? "区域总览" : "All regions"}
      </LocaleLink>

      {/* 页头 · 地区 */}
      <div className="flex flex-wrap items-center justify-between gap-4 pb-4 border-b border-line">
        <div className="flex items-center gap-3">
          <span className="text-3xl">{flag(region)}</span>
          <div>
            <h1 className="font-display font-extrabold text-cream text-2xl sm:text-3xl tracking-tight leading-none">{regionLabel(region, lang)}</h1>
            <div className="mt-1 text-sm text-neutral-500">{regionSource(region)}{summary ? ` · ${fmtCompact(summary.posts)} ${zh ? "帖" : "posts"} · ${summary.tickers} ${zh ? "标的" : "tickers"}` : ""}</div>
          </div>
        </div>
      </div>

      {/* 大数字 KPI 行 */}
      <Counters>
        <Counter label={zh ? "整体情绪" : "Sentiment"} value={(m.pulse.sentiment > 0 ? "+" : "") + m.pulse.sentiment.toFixed(2)} sub={`${m.pulse.sentimentChange > 0 ? "+" : ""}${m.pulse.sentimentChange.toFixed(2)}`} tone={m.pulse.sentiment >= 0 ? "text-bull" : "text-bear"} />
        <Counter label={zh ? "活跃度" : "Activity"} value={`×${m.pulse.activity}`} sub={zh ? "vs 常态" : "vs base"} />
        <Counter label={zh ? "风险偏好" : "Risk"} value={String(m.pulse.riskIndex)} sub="0–100" tone={m.pulse.riskIndex > 66 ? "text-bear" : m.pulse.riskIndex > 40 ? "text-amber" : "text-bull"} />
        <Counter label={zh ? "真人占比" : "Human"} value={`${m.pulse.humanPct}%`} sub={zh ? "信噪比" : "signal"} tone={m.pulse.humanPct >= 60 ? "text-bull" : "text-amber"} />
        <Counter label={zh ? "多空倾向" : "Bull tilt"} value={`${m.pulse.bullPct}%`} sub={zh ? "看多" : "bull"} tone={m.pulse.bullPct >= 50 ? "text-bull" : "text-bear"} />
        <Counter label={zh ? "今日增量" : "Today Δ"} value={`+${m.trigger.volumeDelta}%`} sub={zh ? "讨论量" : "volume"} tone="text-bull" />
      </Counters>

      {/* 今日引爆 */}
      <Module title={zh ? "今日引爆" : "Today's trigger"} icon="flame" accent="reddit"
        right={<span className={`text-[11px] px-2 py-0.5 rounded-full ring-1 ring-inset ${m.trigger.scope === "global" ? "bg-reddit/15 text-reddit ring-reddit/30" : "bg-amber/15 text-amber ring-amber/30"}`}>{m.trigger.scope === "global" ? (zh ? "全球事件" : "Global") : zh ? "本地事件" : "Local"}</span>}>
        <p className="text-[17px] sm:text-[19px] text-cream font-medium leading-snug max-w-3xl">{bi(m.trigger.headline, lang)}</p>
        <div className="mt-4 flex flex-wrap items-center gap-x-8 gap-y-3">
          <div><div className="text-[10px] uppercase tracking-wider text-neutral-500">{zh ? "讨论量增量" : "Volume Δ"}</div><div className="mt-0.5 font-display font-bold text-bull text-[22px] tabular">+{m.trigger.volumeDelta}%</div></div>
          <div><div className="text-[10px] uppercase tracking-wider text-neutral-500">{zh ? "情绪转向" : "Sentiment shift"}</div><div className="mt-0.5 text-[22px] font-display font-bold tabular"><SentScore score={m.trigger.sentimentShift} /></div></div>
          <div className="flex-1 min-w-[200px]">
            <div className="text-[10px] uppercase tracking-wider text-neutral-500 mb-1.5">{zh ? "影响标的" : "Affected tickers"}</div>
            <div className="flex flex-wrap gap-1.5">
              {m.trigger.targets.map((t) => (
                <LocaleLink key={t} href={`/tickers/${t}`} className="inline-flex items-center gap-1 rounded-md bg-white/[.05] px-2 py-1 text-[12px] font-mono text-neutral-300 ring-1 ring-inset ring-white/10 hover:text-reddit transition"><TickerLogo ticker={t} size={16} />{t}</LocaleLink>
              ))}
            </div>
          </div>
        </div>
      </Module>

      {/* 地区脉搏（活跃度趋势）*/}
      <Module title={zh ? "地区脉搏" : "Region pulse"} icon="pulse" accent="bull" hint={zh ? "近期活跃度走势 · 多空占比" : "recent activity trend · bull/bear split"}>
        <MiniTrend data={m.pulse.spark} color="#57D7BA" height={120} />
        <div className="mt-3"><StanceBar bull={m.pulse.bullPct} bear={100 - m.pulse.bullPct} neutral={0} /></div>
        <div className="mt-1.5 flex justify-between text-[11px] text-neutral-500"><span>{zh ? "看多" : "Bull"} {m.pulse.bullPct}%</span><span>{zh ? "看空" : "Bear"} {100 - m.pulse.bullPct}%</span></div>
      </Module>

      {/* 热榜 & 发现（大表）*/}
      <Module title={zh ? "热榜 & 发现" : "Hot list & discovery"} icon="trend" accent="reddit" hint={zh ? "绝对热榜 / 飙升榜 / 新晋" : "top / surging / new"} flush>
        <HotList abs={m.hot.abs} surge={m.hot.surge} fresh={m.hot.fresh} lang={lang} />
      </Module>

      {/* 地区异动 | 注意力轮动（2-up）*/}
      <div className="grid lg:grid-cols-2 gap-5 items-start">
        <Module title={zh ? "地区异动" : "Region anomalies"} icon="flame" accent="amber">
          <div className="divide-y divide-line">
            {m.anomalies.map((a, i) => (
              <LocaleLink key={i} href={`/tickers/${a.target}`} className="flex flex-wrap items-center gap-2.5 py-3 first:pt-0 last:pb-0 hover:opacity-80 transition">
                <TickerLogo ticker={a.target} size={22} />
                <span className="font-mono font-bold text-cream w-14">{a.target}</span>
                <span className="text-[11px] px-1.5 py-0.5 rounded bg-white/[.05] text-neutral-300 ring-1 ring-inset ring-white/10">{bi(a.dim, lang)}</span>
                <Arrow up={a.direction === "up"} className="text-[11px]" />
                <SigmaBadge sigma={a.sigma} />
                <span className="text-[11px] text-neutral-500 flex-1 truncate min-w-[100px]">{bi(a.attribution, lang)}</span>
                <span className="text-[10px] text-neutral-600 tabular">{a.sinceHours}h</span>
              </LocaleLink>
            ))}
          </div>
        </Module>

        <Module title={zh ? "注意力轮动" : "Attention rotation"} icon="trend" accent="amber" hint={zh ? "板块热度变化 · 流向" : "sector heat change · flow"}>
          <ChangeBars height={196} items={m.rotation.map((r) => ({ label: bi(r.sector, lang), value: r.change }))} />
          <div className="mt-3 pt-3 border-t border-line flex items-center justify-between gap-2">
            <div className="rounded-lg bg-bear/[.08] ring-1 ring-inset ring-bear/20 px-3 py-2 text-center flex-1"><div className="text-[10px] text-neutral-500">{zh ? "流出" : "Out of"}</div><div className="mt-0.5 text-[13px] font-semibold text-cream">{bi(m.rotateFrom, lang)}</div></div>
            <span className="text-reddit text-xl shrink-0">→</span>
            <div className="rounded-lg bg-bull/[.08] ring-1 ring-inset ring-bull/20 px-3 py-2 text-center flex-1"><div className="text-[10px] text-neutral-500">{zh ? "流入" : "Into"}</div><div className="mt-0.5 text-[13px] font-semibold text-cream">{bi(m.rotateTo, lang)}</div></div>
          </div>
        </Module>
      </div>

      {/* 地区独有叙事 | 地区性格画像（2-up）*/}
      <div className="grid lg:grid-cols-2 gap-5 items-start">
        <Module title={zh ? "地区独有叙事" : "Region-unique narratives"} icon="doc" accent="reddit" hint={zh ? "本地才有的故事" : "only-here stories"}>
          <div className="divide-y divide-line">
            {m.uniqueNarratives.map((n, i) => (
              <div key={i} className="py-3 first:pt-0 last:pb-0">
                <div className="flex items-center justify-between gap-2">
                  <p className="font-semibold text-cream text-[14px]">{bi(n.topic, lang)}</p>
                  <div className="flex items-center gap-2 text-[11px] shrink-0">
                    <span className="text-reddit font-mono">×{n.heatVsBase}</span>
                    <SentScore score={n.sentiment} className="text-[12px]" />
                    {n.isNewVar && <span className="text-[10px] px-1 py-0.5 rounded bg-reddit/15 text-reddit ring-1 ring-inset ring-reddit/30">{zh ? "新" : "NEW"}</span>}
                  </div>
                </div>
                <div className="mt-1 text-[10px] text-neutral-600">{zh ? "本地背景：" : "Local: "}{bi(n.note, lang)}</div>
                <div className="mt-2 flex flex-wrap gap-1.5">
                  {n.tickers.map((t) => (
                    <LocaleLink key={t} href={`/tickers/${t}`} className="inline-flex items-center gap-1 rounded-md bg-white/[.05] px-1.5 py-0.5 text-[11px] font-mono text-neutral-300 ring-1 ring-inset ring-white/10 hover:text-reddit transition"><TickerLogo ticker={t} size={14} />{t}</LocaleLink>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </Module>

        <Module title={zh ? "地区性格画像" : "Region personality"} icon="layers" accent="reddit" hint={zh ? "半静态特征" : "semi-static"}>
          <div className="grid grid-cols-[1fr_180px] gap-4 items-center">
            <div className="grid grid-cols-2 gap-x-4 gap-y-3.5">
              {[
                { l: zh ? "杠杆度" : "Leverage", v: m.persona.leverage },
                { l: zh ? "投机/迷因" : "Meme", v: m.persona.meme },
                { l: zh ? "短线倾向" : "Short-term", v: m.persona.shortTerm },
                { l: zh ? "内容质量" : "Quality", v: m.persona.quality },
                { l: zh ? "集中度" : "Concentration", v: m.persona.concentration },
              ].map((s, i) => (
                <div key={i}><div className="text-[10px] uppercase tracking-wider text-neutral-500">{s.l}</div><div className="mt-0.5 font-display font-bold text-cream text-[17px] tabular">{s.v}</div></div>
              ))}
              <div className="rounded-lg bg-reddit/[.06] ring-1 ring-inset ring-reddit/20 px-2.5 py-1.5 self-center"><div className="text-[9px] uppercase tracking-wider text-neutral-500">{zh ? "主导人群" : "Persona"}</div><div className="font-display font-bold text-reddit text-[13px]">{bi(m.persona.persona, lang)}</div></div>
            </div>
            <AsiaRadar
              height={200}
              indicators={[
                { name: zh ? "杠杆" : "Lev", max: 100 }, { name: zh ? "迷因" : "Meme", max: 100 },
                { name: zh ? "短线" : "ST", max: 100 }, { name: zh ? "质量" : "Qual", max: 100 }, { name: zh ? "集中" : "Conc", max: 100 },
              ]}
              series={[{ name: regionLabel(region, lang), color: regionColor(region), value: [m.persona.leverage, m.persona.meme, m.persona.shortTerm, m.persona.quality, m.persona.concentration] }]}
            />
          </div>
        </Module>
      </div>

      {/* 本区 vs 全球（大）*/}
      <Module title={zh ? "本区 vs 全球" : "Region vs global"} icon="layers" accent="bull" hint={zh ? "差值 = 本区 − 全球均值" : "diff = region − global avg"}>
        <div className="grid lg:grid-cols-2 gap-6">
          <div>
            <div className="text-[11px] uppercase tracking-wider text-neutral-500 mb-1">{zh ? "各维度偏离" : "Deviation by dimension"}</div>
            <AsiaDivergingBars height={216} items={m.vsGlobal.map((d) => ({ label: bi(d.dim, lang), value: d.diff }))} />
          </div>
          <div className="lg:border-l lg:border-line lg:pl-6">
            <div className="text-[11px] uppercase tracking-wider text-neutral-500 text-center">{zh ? "本区 vs 全球均值" : "Region vs global"}</div>
            <AsiaRadar
              height={228}
              indicators={m.vsGlobal.map((d) => ({ name: bi(d.dim, lang), max: 100 }))}
              series={[
                { name: regionLabel(region, lang), color: regionColor(region), value: m.vsGlobal.map((d) => d.local) },
                { name: zh ? "全球均值" : "Global", color: "#7a8a96", value: m.vsGlobal.map((d) => d.global) },
              ]}
            />
          </div>
        </div>
        <div className="mt-4 pt-4 border-t border-line flex items-start gap-2">
          <span className="text-[11px] uppercase tracking-wider text-amber shrink-0 mt-0.5">{zh ? "显著偏离" : "Standout"}</span>
          <p className="text-[14px] text-cream">{bi(m.standout, lang)}</p>
        </div>
      </Module>

      <p className="text-[11px] text-neutral-600 text-center pt-1">
        {zh ? "脉搏 / 异动 / 性格画像等模块为演示数据（mock），用于展示模块设计；接入真实管线后替换。" : "Modules use mock demo data to showcase the design; to be wired to the real pipeline."}
      </p>
    </div>
  );
}
