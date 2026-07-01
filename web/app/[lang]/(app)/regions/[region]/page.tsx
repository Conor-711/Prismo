import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { SentScore, StanceBar } from "@/components/prismo/Bits";
import { TickerLogo } from "@/components/prismo/TickerLogo";
import { AsiaRadar, AsiaDivergingBars } from "@/components/asia/AsiaCharts";
import { MiniTrend, ChangeBars } from "@/components/prismo/DetailCharts";
import { HotList } from "@/components/prismo/HotList";
import { Module, Counter, Counters, SigmaBadge, Arrow, bi, flag } from "@/components/prismo/DetailBits";
import { ViewportWorkspace } from "@/components/prismo/ViewportWorkspace";
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
    <ViewportWorkspace className="grid min-h-0 grid-rows-[auto_auto_minmax(0,1fr)_auto] gap-3 overflow-hidden" bottomOffset={16}>
      <div className="flex items-center gap-3 px-1 py-1">
        <LocaleLink href="/regions" className="grid h-8 w-8 shrink-0 place-items-center rounded-lg text-neutral-500 ring-1 ring-inset ring-line transition hover:text-reddit">
          ←
        </LocaleLink>
        <span className="text-3xl">{flag(region)}</span>
        <div className="min-w-0">
          <h1 className="font-display text-2xl font-extrabold leading-none tracking-tight text-cream sm:text-3xl">{regionLabel(region, lang)}</h1>
          <div className="mt-1 truncate text-sm text-neutral-500">{regionSource(region)}{summary ? ` · ${fmtCompact(summary.posts)} ${zh ? "帖" : "posts"} · ${summary.tickers} ${zh ? "标的" : "tickers"}` : ""}</div>
        </div>
      </div>

      <Counters>
        <Counter label={zh ? "整体情绪" : "Sentiment"} value={(m.pulse.sentiment > 0 ? "+" : "") + m.pulse.sentiment.toFixed(2)} sub={`${m.pulse.sentimentChange > 0 ? "+" : ""}${m.pulse.sentimentChange.toFixed(2)}`} tone={m.pulse.sentiment >= 0 ? "text-bull" : "text-bear"} />
        <Counter label={zh ? "活跃度" : "Activity"} value={`×${m.pulse.activity}`} sub={zh ? "vs 常态" : "vs base"} />
        <Counter label={zh ? "风险偏好" : "Risk"} value={String(m.pulse.riskIndex)} sub="0–100" tone={m.pulse.riskIndex > 66 ? "text-bear" : m.pulse.riskIndex > 40 ? "text-amber" : "text-bull"} />
        <Counter label={zh ? "真人占比" : "Human"} value={`${m.pulse.humanPct}%`} sub={zh ? "信噪比" : "signal"} tone={m.pulse.humanPct >= 60 ? "text-bull" : "text-amber"} />
        <Counter label={zh ? "多空倾向" : "Bull tilt"} value={`${m.pulse.bullPct}%`} sub={zh ? "看多" : "bull"} tone={m.pulse.bullPct >= 50 ? "text-bull" : "text-bear"} />
        <Counter label={zh ? "今日增量" : "Today Δ"} value={`+${m.trigger.volumeDelta}%`} sub={zh ? "讨论量" : "volume"} tone="text-bull" />
      </Counters>

      <div className="grid min-h-0 gap-3 lg:grid-cols-[320px_minmax(0,1fr)_390px]">
        <aside className="min-h-0 space-y-3 overflow-y-auto pr-1">
          <Module
            title={zh ? "今日引爆" : "Today's trigger"}
            icon="flame"
            accent="reddit"
            bodyClassName="p-4"
            right={<span className={`text-[11px] px-2 py-0.5 rounded-full ring-1 ring-inset ${m.trigger.scope === "global" ? "bg-reddit/15 text-reddit ring-reddit/30" : "bg-amber/15 text-amber ring-amber/30"}`}>{m.trigger.scope === "global" ? (zh ? "全球事件" : "Global") : zh ? "本地事件" : "Local"}</span>}
          >
            <p className="text-[15px] font-medium leading-snug text-cream">{bi(m.trigger.headline, lang)}</p>
            <div className="mt-4 grid grid-cols-2 gap-3">
              <div><div className="text-[10px] uppercase tracking-wider text-neutral-500">{zh ? "讨论量增量" : "Volume Δ"}</div><div className="mt-0.5 font-display text-[22px] font-bold tabular text-bull">+{m.trigger.volumeDelta}%</div></div>
              <div><div className="text-[10px] uppercase tracking-wider text-neutral-500">{zh ? "情绪转向" : "Sentiment shift"}</div><div className="mt-0.5 font-display text-[22px] font-bold tabular"><SentScore score={m.trigger.sentimentShift} /></div></div>
            </div>
            <div className="mt-3">
              <div className="mb-1.5 text-[10px] uppercase tracking-wider text-neutral-500">{zh ? "影响标的" : "Affected tickers"}</div>
              <div className="flex flex-wrap gap-1.5">
                {m.trigger.targets.map((t) => (
                  <LocaleLink key={t} href={`/tickers/${t}`} className="inline-flex items-center gap-1 rounded-md bg-white/[.05] px-2 py-1 text-[12px] font-mono text-neutral-300 ring-1 ring-inset ring-white/10 transition hover:text-reddit"><TickerLogo ticker={t} size={16} />{t}</LocaleLink>
                ))}
              </div>
            </div>
          </Module>

          <Module title={zh ? "地区脉搏" : "Region pulse"} icon="pulse" accent="bull" hint={zh ? "近期活跃度走势 · 多空占比" : "recent activity trend · bull/bear split"} bodyClassName="p-4">
            <MiniTrend data={m.pulse.spark} color="#57D7BA" height={118} />
            <div className="mt-3"><StanceBar bull={m.pulse.bullPct} bear={100 - m.pulse.bullPct} neutral={0} /></div>
            <div className="mt-1.5 flex justify-between text-[11px] text-neutral-500"><span>{zh ? "看多" : "Bull"} {m.pulse.bullPct}%</span><span>{zh ? "看空" : "Bear"} {100 - m.pulse.bullPct}%</span></div>
          </Module>

          <Module title={zh ? "注意力轮动" : "Attention rotation"} icon="trend" accent="amber" hint={zh ? "板块热度变化 · 流向" : "sector heat change · flow"} bodyClassName="p-4">
            <ChangeBars height={178} items={m.rotation.map((r) => ({ label: bi(r.sector, lang), value: r.change }))} />
            <div className="mt-3 flex items-center justify-between gap-2 border-t border-line pt-3">
              <div className="flex-1 rounded-lg bg-bear/[.08] px-3 py-2 text-center ring-1 ring-inset ring-bear/20"><div className="text-[10px] text-neutral-500">{zh ? "流出" : "Out of"}</div><div className="mt-0.5 text-[13px] font-semibold text-cream">{bi(m.rotateFrom, lang)}</div></div>
              <span className="shrink-0 text-xl text-reddit">→</span>
              <div className="flex-1 rounded-lg bg-bull/[.08] px-3 py-2 text-center ring-1 ring-inset ring-bull/20"><div className="text-[10px] text-neutral-500">{zh ? "流入" : "Into"}</div><div className="mt-0.5 text-[13px] font-semibold text-cream">{bi(m.rotateTo, lang)}</div></div>
            </div>
          </Module>
        </aside>

        <section className="grid min-h-0 grid-rows-[minmax(0,1fr)_auto] gap-3">
          <Module
            title={zh ? "热榜 & 发现" : "Hot list & discovery"}
            icon="trend"
            accent="reddit"
            hint={zh ? "绝对热榜 / 飙升榜 / 新晋" : "top / surging / new"}
            className="flex h-full min-h-0 flex-col"
            bodyClassName="min-h-0 flex-1 overflow-auto"
          >
            <HotList abs={m.hot.abs} surge={m.hot.surge} fresh={m.hot.fresh} lang={lang} />
          </Module>

          <Module title={zh ? "地区异动" : "Region anomalies"} icon="flame" accent="amber" bodyClassName="p-0">
            <div className="max-h-[190px] divide-y divide-line overflow-auto px-5">
              {m.anomalies.map((a, i) => (
                <LocaleLink key={i} href={`/tickers/${a.target}`} className="flex flex-wrap items-center gap-2.5 py-3 first:pt-0 last:pb-0 transition hover:opacity-80">
                  <TickerLogo ticker={a.target} size={22} />
                  <span className="w-14 font-mono font-bold text-cream">{a.target}</span>
                  <span className="rounded bg-white/[.05] px-1.5 py-0.5 text-[11px] text-neutral-300 ring-1 ring-inset ring-white/10">{bi(a.dim, lang)}</span>
                  <Arrow up={a.direction === "up"} className="text-[11px]" />
                  <SigmaBadge sigma={a.sigma} />
                  <span className="min-w-[100px] flex-1 truncate text-[11px] text-neutral-500">{bi(a.attribution, lang)}</span>
                  <span className="tabular text-[10px] text-neutral-600">{a.sinceHours}h</span>
                </LocaleLink>
              ))}
            </div>
          </Module>
        </section>

        <aside className="min-h-0 space-y-3 overflow-y-auto pr-1">
          <Module title={zh ? "地区独有叙事" : "Region-unique narratives"} icon="doc" accent="reddit" hint={zh ? "本地才有的故事" : "only-here stories"} bodyClassName="p-4">
            <div className="divide-y divide-line">
              {m.uniqueNarratives.map((n, i) => (
                <div key={i} className="py-3 first:pt-0 last:pb-0">
                  <div className="flex items-center justify-between gap-2">
                    <p className="text-[14px] font-semibold text-cream">{bi(n.topic, lang)}</p>
                    <div className="flex shrink-0 items-center gap-2 text-[11px]">
                      <span className="font-mono text-reddit">×{n.heatVsBase}</span>
                      <SentScore score={n.sentiment} className="text-[12px]" />
                      {n.isNewVar && <span className="rounded bg-reddit/15 px-1 py-0.5 text-[10px] text-reddit ring-1 ring-inset ring-reddit/30">{zh ? "新" : "NEW"}</span>}
                    </div>
                  </div>
                  <div className="mt-1 text-[10px] text-neutral-600">{zh ? "本地背景：" : "Local: "}{bi(n.note, lang)}</div>
                  <div className="mt-2 flex flex-wrap gap-1.5">
                    {n.tickers.map((t) => (
                      <LocaleLink key={t} href={`/tickers/${t}`} className="inline-flex items-center gap-1 rounded-md bg-white/[.05] px-1.5 py-0.5 text-[11px] font-mono text-neutral-300 ring-1 ring-inset ring-white/10 transition hover:text-reddit"><TickerLogo ticker={t} size={14} />{t}</LocaleLink>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          </Module>

          <Module title={zh ? "地区性格画像" : "Region personality"} icon="layers" accent="reddit" hint={zh ? "半静态特征" : "semi-static"} bodyClassName="p-4">
            <div className="grid grid-cols-[1fr_160px] items-center gap-3">
              <div className="grid grid-cols-2 gap-x-4 gap-y-3">
                {[
                  { l: zh ? "杠杆度" : "Leverage", v: m.persona.leverage },
                  { l: zh ? "投机/迷因" : "Meme", v: m.persona.meme },
                  { l: zh ? "短线倾向" : "Short-term", v: m.persona.shortTerm },
                  { l: zh ? "内容质量" : "Quality", v: m.persona.quality },
                  { l: zh ? "集中度" : "Concentration", v: m.persona.concentration },
                ].map((s, i) => (
                  <div key={i}><div className="text-[10px] uppercase tracking-wider text-neutral-500">{s.l}</div><div className="mt-0.5 font-display text-[17px] font-bold tabular text-cream">{s.v}</div></div>
                ))}
                <div className="self-center rounded-lg bg-reddit/[.06] px-2.5 py-1.5 ring-1 ring-inset ring-reddit/20"><div className="text-[9px] uppercase tracking-wider text-neutral-500">{zh ? "主导人群" : "Persona"}</div><div className="font-display text-[13px] font-bold text-reddit">{bi(m.persona.persona, lang)}</div></div>
              </div>
              <AsiaRadar
                height={178}
                indicators={[
                  { name: zh ? "杠杆" : "Lev", max: 100 }, { name: zh ? "迷因" : "Meme", max: 100 },
                  { name: zh ? "短线" : "ST", max: 100 }, { name: zh ? "质量" : "Qual", max: 100 }, { name: zh ? "集中" : "Conc", max: 100 },
                ]}
                series={[{ name: regionLabel(region, lang), color: regionColor(region), value: [m.persona.leverage, m.persona.meme, m.persona.shortTerm, m.persona.quality, m.persona.concentration] }]}
              />
            </div>
          </Module>

          <Module title={zh ? "本区 vs 全球" : "Region vs global"} icon="layers" accent="bull" hint={zh ? "差值 = 本区 − 全球均值" : "diff = region − global avg"} bodyClassName="p-4">
            <div>
              <div className="mb-1 text-[11px] uppercase tracking-wider text-neutral-500">{zh ? "各维度偏离" : "Deviation by dimension"}</div>
              <AsiaDivergingBars height={184} items={m.vsGlobal.map((d) => ({ label: bi(d.dim, lang), value: d.diff }))} />
            </div>
            <div className="mt-4 border-t border-line pt-4">
              <div className="text-center text-[11px] uppercase tracking-wider text-neutral-500">{zh ? "本区 vs 全球均值" : "Region vs global"}</div>
              <AsiaRadar
                height={196}
                indicators={m.vsGlobal.map((d) => ({ name: bi(d.dim, lang), max: 100 }))}
                series={[
                  { name: regionLabel(region, lang), color: regionColor(region), value: m.vsGlobal.map((d) => d.local) },
                  { name: zh ? "全球均值" : "Global", color: "#7a8a96", value: m.vsGlobal.map((d) => d.global) },
                ]}
              />
            </div>
            <div className="mt-4 flex items-start gap-2 border-t border-line pt-4">
              <span className="mt-0.5 shrink-0 text-[11px] uppercase tracking-wider text-amber">{zh ? "显著偏离" : "Standout"}</span>
              <p className="text-[14px] text-cream">{bi(m.standout, lang)}</p>
            </div>
          </Module>
        </aside>
      </div>

      <p className="text-center text-[11px] text-neutral-600">
        {zh ? "脉搏 / 异动 / 性格画像等模块为演示数据（mock），用于展示模块设计；接入真实管线后替换。" : "Modules use mock demo data to showcase the design; to be wired to the real pipeline."}
      </p>
    </ViewportWorkspace>
  );
}
