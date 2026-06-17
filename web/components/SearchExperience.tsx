"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { LocaleLink } from "./i18n/LocaleLink";
import { useLocale } from "./i18n/LocaleProvider";
import { withLang } from "@/lib/i18n";
import { IconSearch, IconArrow } from "./icons";
import { recordSearch } from "@/lib/searchCounts";
import { track } from "@/lib/analytics";
import { SearchLeaderboard, type HeatItem } from "./SearchLeaderboard";

export interface ValidTicker { ticker: string; name: string; posts: number; base?: string }

// 搜索页主体：占据整页的搜索入口 + 搜索热度榜；搜不到 / 数据不足时进入专门提示页。
export function SearchExperience({
  valid,
  popular,
  heat,
  tickerBase = "/ticker",
}: {
  valid: ValidTicker[];
  popular: string[];
  heat: HeatItem[];
  tickerBase?: string;
}) {
  const router = useRouter();
  const { lang, dict } = useLocale();
  const t = dict.searchHero;
  const ts = dict.search;

  const [v, setV] = useState("");
  const [missQ, setMissQ] = useState<string | null>(null); // 非空 = 展示提示页（值为用户查询）

  const validSet = useMemo(() => new Set(valid.map((x) => x.ticker)), [valid]);
  const names = useMemo(() => {
    const m: Record<string, string> = {};
    for (const x of valid) m[x.ticker] = x.name;
    return m;
  }, [valid]);
  // 每个标的的个股页前缀（全站搜索里 美股→/ticker、中概港股→/cn/ticker），缺省回退 tickerBase。
  const baseOf = useMemo(() => {
    const m: Record<string, string> = {};
    for (const x of valid) m[x.ticker] = x.base ?? tickerBase;
    return m;
  }, [valid, tickerBase]);

  const go = (e: React.FormEvent) => {
    e.preventDefault();
    const sym = v.trim().toUpperCase().replace(/^\$/, "");
    if (!sym) return;
    // 先按代码精确命中；否则回退按公司名解析（NOKIA→NOK、INTEL→INTC、SPACEX→SPCX…）。
    const target = validSet.has(sym) ? sym : resolveByName(sym, valid);
    if (target) {
      void recordSearch(target); // 记一次真实搜索（fire-and-forget）
      track("search", { lang, ticker: target, meta: { found: true, q: sym } });
      router.push(withLang(lang, `${baseOf[target] ?? tickerBase}/${encodeURIComponent(target)}`));
    } else {
      track("search", { lang, ticker: sym, meta: { found: false, q: sym } });
      setMissQ(sym); // 跳提示页
    }
  };

  const suggestions = useMemo(() => (missQ ? suggest(missQ, valid) : []), [missQ, valid]);

  // ---------- 专门提示页：搜不到 / 数据不足 ----------
  if (missQ) {
    return (
      <div className="min-h-[60vh] flex flex-col items-center justify-center text-center py-12">
        <div className="grid place-items-center w-16 h-16 rounded-2xl bg-white/[.04] ring-1 ring-inset ring-line text-neutral-500 mb-5">
          <IconSearch className="w-7 h-7" />
        </div>
        <div className="eyebrow text-neutral-500">{ts.notFoundEyebrow}</div>
        <h1 className="mt-2 font-display font-extrabold text-cream tracking-tight text-[clamp(22px,3.4vw,30px)] leading-tight">
          {ts.notFoundTitle.replace("{q}", missQ)}
        </h1>
        <p className="mt-3 text-sm text-neutral-500 max-w-md leading-relaxed">{ts.notFoundDesc}</p>

        <ul className="mt-5 space-y-1.5 text-sm text-neutral-400 text-left">
          <li className="flex gap-2"><span className="text-reddit">·</span>{ts.reasonTyped}</li>
          <li className="flex gap-2"><span className="text-reddit">·</span>{ts.reasonData}</li>
        </ul>

        {suggestions.length > 0 && (
          <div className="mt-7 w-full max-w-md">
            <div className="text-xs text-neutral-500 mb-2">{ts.didYouMean}</div>
            <div className="flex flex-wrap justify-center gap-2">
              {suggestions.map((sym) => (
                <LocaleLink key={sym} href={`${baseOf[sym] ?? tickerBase}/${sym}`} className={chipCls}>
                  <span className="font-mono font-semibold">{sym}</span>
                  {names[sym] && <span className="text-neutral-500 ml-1.5 hidden sm:inline">{names[sym]}</span>}
                </LocaleLink>
              ))}
            </div>
          </div>
        )}

        <div className="mt-6 w-full max-w-md">
          <div className="text-xs text-neutral-500 mb-2">{ts.tryPopular}</div>
          <div className="flex flex-wrap justify-center gap-2">
            {popular.slice(0, 8).map((sym) => (
              <LocaleLink key={sym} href={`${baseOf[sym] ?? tickerBase}/${sym}`} className={chipCls}>
                <span className="font-mono font-medium">{sym}</span>
              </LocaleLink>
            ))}
          </div>
        </div>

        <button
          onClick={() => {
            setMissQ(null);
            setV("");
          }}
          className="mt-8 inline-flex items-center gap-1.5 rounded-lg px-5 py-2.5 font-display font-bold text-white text-sm hover:brightness-110 transition"
          style={{ backgroundImage: "var(--grad-brand)" }}
        >
          <IconSearch className="w-4 h-4" />
          {ts.back}
        </button>
      </div>
    );
  }

  // ---------- 默认：搜索为整页主体 + 热度榜 ----------
  return (
    <div className="py-6 sm:py-10">
      {/* 搜索 hero —— 页面主体，不再局限于卡片 */}
      <section className="text-center max-w-2xl mx-auto">
        <div className="eyebrow text-reddit">{t.eyebrow}</div>
        <h1 className="mt-3 font-display font-extrabold text-cream tracking-tight text-[clamp(26px,4.4vw,42px)] leading-[1.08]">
          {t.title}
        </h1>
        <p className="mt-3 text-[15px] text-neutral-400 leading-relaxed">
          {t.subPre}
          <span className="text-bull font-medium">{t.subBull}</span> ⚔{" "}
          <span className="text-bear font-medium">{t.subBear}</span>
          {t.subPost}
        </p>

        <form onSubmit={go} className="mt-7 relative">
          <IconSearch className="w-5 h-5 absolute left-5 top-1/2 -translate-y-1/2 text-neutral-500" />
          <input
            value={v}
            onChange={(e) => setV(e.target.value)}
            placeholder={t.placeholder}
            autoFocus
            className="w-full h-14 sm:h-[3.75rem] bg-ink/70 border border-line rounded-2xl pl-12 pr-36 text-[16px] sm:text-[17px] text-neutral-100 placeholder:text-neutral-600 shadow-lg shadow-black/20 focus:outline-none focus:border-reddit/55 focus:ring-2 focus:ring-reddit/20 transition"
          />
          <button
            type="submit"
            className="group absolute right-2.5 top-1/2 -translate-y-1/2 inline-flex items-center gap-1.5 rounded-xl px-5 py-3 font-display font-bold text-white text-sm hover:brightness-110 transition"
            style={{ backgroundImage: "var(--grad-brand)" }}
          >
            {t.cta}
            <IconArrow className="w-4 h-4 group-hover:translate-x-0.5 transition" />
          </button>
        </form>

        {popular.length > 0 && (
          <div className="mt-4 flex flex-wrap items-center justify-center gap-2 text-xs text-neutral-500">
            <span>{t.popular}</span>
            {popular.map((sym) => (
              <LocaleLink key={sym} href={`${baseOf[sym] ?? tickerBase}/${sym}`} className={chipCls}>
                <span className="font-mono font-medium">{sym}</span>
              </LocaleLink>
            ))}
          </div>
        )}
      </section>

      {/* 搜索热度榜 */}
      <div className="mt-12 sm:mt-16 max-w-xl mx-auto">
        <SearchLeaderboard heat={heat} names={names} tickerBase={tickerBase} bases={baseOf} />
      </div>
    </div>
  );
}

const chipCls =
  "font-mono px-2.5 py-1 rounded-lg bg-white/[.04] text-neutral-300 hover:bg-reddit/15 hover:text-reddit ring-1 ring-inset ring-white/8 transition text-xs";

// 按公司名解析到 ticker：用户输入「NOKIA / INTEL / SPACEX」等公司名而非代码时，
// 回退到名称匹配（名称完全相同 > 名称以查询开头 > 查询是名称中的整词）。
// valid 已按讨论量降序 → 命中即最相关；要求 ≥3 字符，避免短词乱匹配。
function resolveByName(q: string, valid: ValidTicker[]): string | null {
  const Q = q.trim().toUpperCase();
  if (Q.length < 3) return null;
  let starts: string | null = null;
  let word: string | null = null;
  for (const x of valid) {
    const N = (x.name || "").toUpperCase();
    if (!N) continue;
    if (N === Q) return x.ticker;
    if (!starts && N.startsWith(Q)) starts = x.ticker;
    if (!word && N.split(/[^A-Z0-9]+/).includes(Q)) word = x.ticker;
  }
  return starts ?? word;
}

// 简单模糊匹配：代码精确/前缀/包含 > 公司名前缀/包含；按相关度 + 讨论量排，取前 6。
function suggest(q: string, valid: ValidTicker[]): string[] {
  const ql = q.toLowerCase();
  return valid
    .map((x) => {
      const tk = x.ticker.toLowerCase();
      const nm = (x.name || "").toLowerCase();
      let s = 0;
      if (tk === ql) s = 100;
      else if (tk.startsWith(ql)) s = 80;
      else if (tk.includes(ql)) s = 60;
      else if (nm.startsWith(ql)) s = 50;
      else if (nm.includes(ql)) s = 30;
      return { x, s };
    })
    .filter((o) => o.s > 0)
    .sort((a, b) => b.s - a.s || b.x.posts - a.x.posts)
    .slice(0, 6)
    .map((o) => o.x.ticker);
}
