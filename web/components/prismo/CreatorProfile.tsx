"use client";

// YouTube 作者页主体（客户端组件：复用 kolShared 的 STANCE/longDay/Avatar——它们是 "use client" 模块，
// 服务端组件不能 dot 进去，故本组件标 "use client"）。数据由 getYoutubeCreator 在 build/SSR 时算好作为 plain props 传入。
// 两块（对应用户需求）：① 标的判断（每标的综合成几点关键判断 + 代表性目标价/周期/关键位 + 当时价→现在价回测）
// ② 互动最高视频。诚实定位：回测基于近一个月价格 → 短窗、样本少，页面显式标注，不包装成长期战绩。
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { Panel } from "@/components/ui";
import { fmtCompact } from "@/lib/format";
import { Avatar } from "./kolShared";
import type { YoutubeCreator, TickerJudgments, Judgment, CreatorVideo } from "@/lib/creatorQueries";
import type { Stance } from "@/lib/mockDetail";

const YT = "#E0A33E";
// 本地立场配色/文案与日期格式：不从 "use client" 的 kolShared dot 进来——其导出在 RSC（generateStaticParams
// 的 static-paths worker）里是 client 引用，顶层 `STANCE.bull.color` 会抛 "cannot dot into a client module"。
// 值与 kolShared.STANCE / longDay 保持一致。
const STANCE_LABEL: Record<Stance, { color: string; zh: string; en: string }> = {
  bull: { color: "#57D7BA", zh: "看多", en: "Bull" },
  bear: { color: "#FF5C6C", zh: "看空", en: "Bear" },
  neutral: { color: "#7A8A96", zh: "中性", en: "Neutral" },
};
const UP = STANCE_LABEL.bull.color;
const DOWN = STANCE_LABEL.bear.color;
const moveColor = (x: number) => (x > 0 ? UP : x < 0 ? DOWN : "#9CA3AF");
const pctStr = (x: number, sign = true) => `${sign && x > 0 ? "+" : ""}${(x * 100).toFixed(1)}%`;
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const longDayLocal = (d: string, zh: boolean) => {
  const [, m, dd] = d.split("-");
  return zh ? `${+m} 月 ${+dd} 日` : `${MONTHS[+m - 1]} ${+dd}`;
};

function StanceTag({ stance, zh }: { stance: Stance; zh: boolean }) {
  const s = STANCE_LABEL[stance];
  return (
    <span className="inline-block rounded px-1.5 py-px text-[10.5px] font-medium" style={{ background: `${s.color}22`, color: s.color }}>
      {zh ? s.zh : s.en}
    </span>
  );
}

function TickerChip({ t }: { t: string }) {
  return (
    <LocaleLink
      href={`/tickers/${t}`}
      className="rounded bg-elevated px-1.5 py-px font-mono text-[10.5px] text-neutral-400 transition hover:text-cream"
    >
      {t}
    </LocaleLink>
  );
}

function SectionHead({ title, hint }: { title: string; hint?: string }) {
  return (
    <div className="mb-3.5">
      <div className="flex items-center gap-2">
        <span className="h-2.5 w-2.5 rounded-full" style={{ background: YT }} />
        <h2 className="font-display text-[15px] font-bold text-cream">{title}</h2>
      </div>
      {hint && <p className="mt-1.5 text-[12px] leading-relaxed text-neutral-500">{hint}</p>}
    </div>
  );
}

// ===== 头部：频道档案 =====
function Header({ p, zh }: { p: YoutubeCreator["profile"]; zh: boolean }) {
  const stats: { label: string; value: string }[] = [];
  if (typeof p.subscribers === "number") stats.push({ label: zh ? "粉丝" : "Subscribers", value: fmtCompact(p.subscribers) });
  if (typeof p.channelVideos === "number") stats.push({ label: zh ? "视频" : "Videos", value: fmtCompact(p.channelVideos) });
  if (typeof p.channelViews === "number") stats.push({ label: zh ? "总播放" : "Total views", value: fmtCompact(p.channelViews) });
  return (
    <div className="px-1 py-1">
      <div className="flex items-start gap-4">
        <Avatar src={p.avatar} color={YT} name={p.name} size={58} />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-x-2.5 gap-y-1">
            <h1 className="font-display text-2xl font-extrabold leading-none tracking-tight text-cream">{p.name}</h1>
            <span className="rounded px-1.5 py-px text-[10px] font-medium" style={{ background: `${YT}22`, color: YT }}>
              YouTube
            </span>
          </div>
          <div className="mt-1.5 flex flex-wrap items-center gap-x-2 gap-y-1 text-[12.5px] text-neutral-500">
            {p.handle && <span className="font-mono text-neutral-400">{p.handle}</span>}
            <span>
              {zh ? "收录" : "Tracked"} {p.trackedVideos} {zh ? "个视频" : "videos"} · {p.trackedTickers} {zh ? "只标的" : "tickers"}
            </span>
            <a href={p.url} target="_blank" rel="noopener noreferrer" className="transition hover:text-cream">
              {zh ? "频道主页 ↗" : "Channel ↗"}
            </a>
          </div>
          {p.bio && <p className="mt-2 max-w-4xl whitespace-pre-line text-[12.5px] leading-relaxed text-neutral-500 line-clamp-2">{p.bio}</p>}
        </div>
        {stats.length > 0 && (
          <div className="grid shrink-0 grid-cols-3 divide-x divide-line overflow-hidden rounded-lg bg-white/[.012] ring-1 ring-inset ring-white/[.06]">
            {stats.map((s) => (
              <div key={s.label} className="min-w-[88px] px-3 py-2">
                <div className="font-display text-lg font-bold leading-none tabular text-cream">{s.value}</div>
                <div className="mt-1 text-[10px] uppercase tracking-wider text-neutral-500">{s.label}</div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

// ===== ① 标的判断 =====
// 刻画作者对每只标的的具体判断（多/空/中性 + 观点/论据 + 目标价）及判断结果回测（当时价→现在价 + 命中）。
// 顶部汇总沿用方向性回测（命中率/平均收益）；下方按标的归组、逐条展开判断。
function Judgments({ creator, zh, fill = false }: { creator: YoutubeCreator; zh: boolean; fill?: boolean }) {
  const tr = creator.trackRecord;
  const groups = creator.tickerJudgments;
  const bench = tr.hasBenchmark;
  const caveat =
    tr.count > 0
      ? zh
        ? `回测基于 ${tr.priceFrom}–${tr.priceTo} 收盘价、自表态日起算（可评估 ${tr.count} 次、平均持有 ${tr.avgHeldDays} 天）· 短窗小样本，仅供参考；表态过近或缺价的判断不计回测。`
        : `Backtest uses ${tr.priceFrom}–${tr.priceTo} closes from each call date (${tr.count} evaluable, avg hold ${tr.avgHeldDays}d) · short window & small sample, indicative only; very recent or price-less calls aren't scored.`
      : zh
        ? "近一个月内暂无可用价格回测其方向性判断；以下仍展示其观点与论据。"
        : "No directional calls with price data to score in the recent window; opinions & arguments still shown below.";

  return (
    <Panel className={`p-4 sm:p-5 ${fill ? "flex h-full min-h-0 flex-col overflow-hidden" : ""}`}>
      <div className="shrink-0">
        <SectionHead
          title={zh ? "① 标的判断" : "① Ticker judgments"}
          hint={zh ? "他对每只标的的多空/中性判断、观点与论据、目标价，以及自表态日起「当时价→现在价」的回测" : "His bull/bear/neutral judgment on each ticker — opinion, arguments, target — and the price-then-vs-now backtest from his call date"}
        />
      </div>
      {tr.count > 0 && (
        <div className="mb-4 grid shrink-0 grid-cols-2 gap-2.5 sm:grid-cols-4">
          <Stat label={zh ? "命中率" : "Hit rate"} value={`${Math.round(tr.hitRate * 100)}%`} sub={`${tr.calls.filter((c) => c.hit).length}/${tr.count}`} tone={tr.hitRate >= 0.5 ? UP : DOWN} />
          <Stat label={zh ? "按方向平均" : "Avg (directional)"} value={pctStr(tr.avgSignedRet)} sub={zh ? "看多/看空修正后" : "stance-adjusted"} tone={moveColor(tr.avgSignedRet)} />
          {bench && <Stat label={zh ? "平均跑赢大盘" : "Avg vs SPY"} value={pctStr(tr.avgExcess)} sub={zh ? "相对 SPY 超额" : "excess over SPY"} tone={moveColor(tr.avgExcess)} />}
          <Stat label={zh ? "可回测判断" : "Scored"} value={String(tr.count)} sub={zh ? `平均持有 ${tr.avgHeldDays} 天` : `avg ${tr.avgHeldDays}d held`} />
        </div>
      )}
      {groups.length > 0 ? (
        <div className={`space-y-3 ${fill ? "min-h-0 flex-1 overflow-y-auto pr-1" : ""}`}>
          {groups.map((g) => (
            <TickerGroup key={g.ticker} g={g} zh={zh} />
          ))}
        </div>
      ) : (
        <p className="text-[13px] text-neutral-500">{zh ? "暂无该作者的标的判断。" : "No ticker judgments for this creator yet."}</p>
      )}
      <p className="mt-3 shrink-0 text-[11px] leading-relaxed text-neutral-600">{caveat}</p>
    </Panel>
  );
}

// 一只标的的判断（综合）：标的 + 综合立场 + 多/空/中性计数 + 代表性回测 · 几点关键判断 · 代表性目标价/周期/关键位 · 原视频。
function TickerGroup({ g, zh }: { g: TickerJudgments; zh: boolean }) {
  const points = (zh ? g.pointsZh : g.pointsEn).length ? (zh ? g.pointsZh : g.pointsEn) : zh ? g.pointsEn : g.pointsZh;
  // 代表性结构化参数：judgments 已倒序 → 取最新一条非空
  const pick = (f: (j: Judgment) => string | undefined) => {
    for (const j of g.judgments) {
      const v = f(j);
      if (v) return v;
    }
    return undefined;
  };
  const target = pick((j) => j.target);
  const horizon = pick((j) => (zh ? j.horizonZh : j.horizonEn) || j.horizonEn || j.horizonZh);
  const keyLevels = pick((j) => (zh ? j.keyLevelsZh : j.keyLevelsEn) || j.keyLevelsEn || j.keyLevelsZh);
  // 代表性回测：最早一条「有价的方向性判断」（自首次表态起 → 现在，窗口最长、最有意义）；judgments 倒序故取末位
  const scored = g.judgments.filter((j) => j.hasPrice && j.hit != null && j.entry != null && j.latest != null);
  const back = scored.length ? scored[scored.length - 1] : undefined;
  return (
    <div className="rounded-xl bg-card p-4 ring-1 ring-inset ring-line">
      {/* 头：标的 + 综合立场 + 计数 + 代表性回测「当时价→现在价」 */}
      <div className="flex flex-wrap items-center gap-2 border-b border-line pb-2.5">
        <LocaleLink href={`/tickers/${g.ticker}`} className="font-mono text-[15px] font-bold text-cream transition hover:text-[#E0A33E]">
          {g.ticker}
        </LocaleLink>
        <StanceTag stance={g.netStance} zh={zh} />
        <span className="flex items-center gap-2 text-[11px] text-neutral-500">
          {g.bull > 0 && <span style={{ color: UP }}>▲ {g.bull}</span>}
          {g.bear > 0 && <span style={{ color: DOWN }}>▼ {g.bear}</span>}
          {g.neutral > 0 && <span className="text-neutral-500">• {g.neutral}</span>}
        </span>
        {back ? (
          <span
            className="ml-auto inline-flex items-center gap-1.5 whitespace-nowrap font-mono text-[11px] tabular"
            title={zh ? `自 ${longDayLocal(back.day, zh)} 表态起算` : `since the call on ${longDayLocal(back.day, zh)}`}
          >
            <span className="text-neutral-500">${back.entry!.toFixed(2)}</span>
            <span className="text-neutral-700">→</span>
            <span className="text-neutral-300">${back.latest!.toFixed(2)}</span>
            <span style={{ color: moveColor(back.ret ?? 0) }}>{pctStr(back.ret ?? 0)}</span>
            {back.hit != null && <span className="font-bold" style={{ color: back.hit ? UP : DOWN }}>{back.hit ? "✓" : "✗"}</span>}
          </span>
        ) : (
          <span className="ml-auto text-[11px] text-neutral-600">{zh ? "暂无回测价" : "no price yet"}</span>
        )}
      </div>
      {/* 几点关键判断（综合该作者对该标的的多条视频，合并去重） */}
      {points.length > 0 && (
        <ul className="mt-2.5 space-y-1.5">
          {points.map((p, i) => (
            <li key={i} className="flex gap-2 text-[12.5px] leading-relaxed text-neutral-300">
              <span className="select-none text-[#E0A33E]">·</span>
              <span>{p}</span>
            </li>
          ))}
        </ul>
      )}
      {/* 代表性目标价/周期/关键位 + 基于几个视频（dated 链接） */}
      <div className="mt-3 flex flex-wrap items-center gap-1.5">
        {target && <MetaChip label={zh ? "目标价" : "Target"} value={target} />}
        {horizon && <MetaChip label={zh ? "周期" : "Horizon"} value={horizon} />}
        {keyLevels && <MetaChip label={zh ? "关键位" : "Levels"} value={keyLevels} />}
        <span className="ml-auto flex flex-wrap items-center gap-x-2 gap-y-1 text-[11px] text-neutral-600">
          <span>{zh ? `基于 ${g.count} 个视频` : `from ${g.count} video${g.count > 1 ? "s" : ""}`}</span>
          {g.judgments.slice(0, 4).map((j) => (
            <a key={j.videoId} href={j.url} target="_blank" rel="noopener noreferrer" title={j.title} className="transition hover:text-[#E0A33E]">
              {longDayLocal(j.day, zh)} ↗
            </a>
          ))}
        </span>
      </div>
    </div>
  );
}

function MetaChip({ label, value }: { label: string; value: string }) {
  return (
    <span className="inline-flex items-center gap-1 rounded bg-elevated px-1.5 py-0.5 text-[10.5px]">
      <span className="text-neutral-600">{label}</span>
      <span className="font-mono text-neutral-300">{value}</span>
    </span>
  );
}

function Stat({ label, value, sub, tone = "#EDEDED" }: { label: string; value: string; sub?: string; tone?: string }) {
  return (
    <div className="rounded-lg bg-card px-3 py-2.5 ring-1 ring-inset ring-line">
      <div className="text-[10px] uppercase tracking-wider text-neutral-500">{label}</div>
      <div className="mt-0.5 font-display text-[19px] font-bold leading-none tabular" style={{ color: tone }}>{value}</div>
      {sub && <div className="mt-1 text-[10.5px] text-neutral-600">{sub}</div>}
    </div>
  );
}

// ===== ② 互动最高视频 =====
function TopVideos({ items, zh, fill = false }: { items: CreatorVideo[]; zh: boolean; fill?: boolean }) {
  if (!items.length) return null;
  return (
    <Panel className={`p-4 sm:p-5 ${fill ? "flex h-full min-h-0 flex-col overflow-hidden" : ""}`}>
      <div className="shrink-0">
        <SectionHead title={zh ? "② 互动最高的视频" : "② Most-watched videos"} hint={zh ? "按播放量排序" : "Ranked by view count"} />
      </div>
      <ul className={`space-y-2.5 ${fill ? "min-h-0 flex-1 overflow-y-auto pr-1" : ""}`}>
        {items.map((v) => (
          <li key={v.videoId} className="flex gap-3 rounded-xl bg-card p-2.5 ring-1 ring-inset ring-line">
            <a href={v.url} target="_blank" rel="noopener noreferrer" className="relative block aspect-video w-32 shrink-0 overflow-hidden rounded-lg bg-elevated">
              {v.thumbnail ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={v.thumbnail} alt="" loading="lazy" className="h-full w-full object-cover" />
              ) : (
                <span className="grid h-full w-full place-items-center text-[10px] text-neutral-600">{v.ticker}</span>
              )}
            </a>
            <div className="flex min-w-0 flex-1 flex-col">
              <a href={v.url} target="_blank" rel="noopener noreferrer" className="text-[13.5px] font-medium leading-snug text-cream transition hover:text-[#E0A33E] line-clamp-2">
                {v.title}
              </a>
              <div className="mt-auto flex flex-wrap items-center gap-x-2 gap-y-1 pt-1.5 text-[11px] text-neutral-500">
                {v.ticker && <TickerChip t={v.ticker} />}
                <StanceTag stance={v.stance} zh={zh} />
                <span>{longDayLocal(v.day, zh)}</span>
                <span className="ml-auto font-mono tabular text-neutral-400">
                  {fmtCompact(v.views)} {zh ? "播放" : "views"}
                </span>
              </div>
            </div>
          </li>
        ))}
      </ul>
    </Panel>
  );
}

export function CreatorProfile({ creator, zh, fill = false }: { creator: YoutubeCreator; zh: boolean; fill?: boolean }) {
  if (fill) {
    return (
      <div className="grid h-full min-h-0 grid-rows-[auto_minmax(0,1fr)] gap-3">
        <Header p={creator.profile} zh={zh} />
        <div className="grid min-h-0 gap-3 lg:grid-cols-[minmax(0,1fr)_390px]">
          <Judgments creator={creator} zh={zh} fill />
          <TopVideos items={creator.topVideos} zh={zh} fill />
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-5">
      <Header p={creator.profile} zh={zh} />
      <Judgments creator={creator} zh={zh} />
      <TopVideos items={creator.topVideos} zh={zh} />
    </div>
  );
}
