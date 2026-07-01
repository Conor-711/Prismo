"use client";

// 标的页「个体观点 · KOL」的观点浏览器（替代原 按KOL/按视角/按热度 三 tab）：
//   顶部 = 筛选条（平台[品牌 logo] / 时间[指定起始日期 + 5 个区间模板] / 语言[简中·英·日·韩·繁中] / 质量）
//   下方 = 主从布局：左窄列 = 帖文卡列表（头像+handle+开头），右宽栏 = 选中帖的完整正文（含原文/译文切换 + 回原帖）
// 全部筛选在前端做；默认按「相关性」降序排（最相关的在前）。数据来自 lib/kolQueries.getKolOpinions（近 ~30 天扁平池）。
import { useMemo, useState } from "react";
import type { KolOpinion, KolSource, KolJudgment, Stance, TweetMetrics, TweetReply } from "@/lib/mockDetail";
import { Avatar, SOURCE, STANCE, pickOriginal, mmdd } from "./kolShared";
import { YtReader } from "./YtReader";
import { fmtCompact } from "@/lib/format";

// X 推文底部互动数行（赞/转/评/看/藏）的小图标 —— 24×24 stroke 路径（Lucide 风），克制中性色。
type StatKey = "replies" | "retweets" | "likes" | "views" | "bookmarks"; // ⊆ keyof TweetMetrics
const STAT_ICON: Record<StatKey, string> = {
  replies: "M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z",
  retweets: "M17 1l4 4-4 4M3 11V9a4 4 0 0 1 4-4h14M7 23l-4-4 4-4M21 13v2a4 4 0 0 1-4 4H3",
  likes: "M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 1 0-7.78 7.78L12 21.23l8.84-8.84a5.5 5.5 0 0 0 0-7.78z",
  views: "M18 20V10M12 20V4M6 20v-6",
  bookmarks: "M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z",
};
function Stat({ kind, n }: { kind: StatKey; n: number }) {
  return (
    <span className="flex items-center gap-1 text-neutral-500" title={kind}>
      <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
        <path d={STAT_ICON[kind]} />
      </svg>
      <span className="font-mono tabular text-[11px]">{fmtCompact(n)}</span>
    </span>
  );
}
// 推文互动数行（仅 X）：reply · retweet · like · view · bookmark，与 X 原生底栏顺序一致。
function TweetStats({ m }: { m: TweetMetrics }) {
  const order: StatKey[] = ["replies", "retweets", "likes", "views", "bookmarks"];
  if (!order.some((k) => (m[k] ?? 0) > 0)) return null;
  return (
    <div className="mt-3 flex items-center gap-4 border-t border-line/60 pt-2.5">
      {order.map((k) => <Stat key={k} kind={k} n={m[k] ?? 0} />)}
    </div>
  );
}
// 帖文下「热门评论」（仅 X）：按点赞 top-N，小头像 + @handle + ❤数 + 评论原文 + 回原帖。
function TweetReplies({ replies, zh }: { replies: TweetReply[]; zh: boolean }) {
  if (!replies?.length) return null;
  return (
    <div className="mt-3 border-t border-line/60 pt-3">
      <div className="mb-2 flex items-center gap-1.5 text-[11px] font-semibold text-neutral-400">
        <svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
          <path d={STAT_ICON.replies} />
        </svg>
        {zh ? "热门评论" : "Top replies"}
      </div>
      <ul className="space-y-2">
        {replies.map((r, i) => (
          <li key={i} className="flex gap-2 rounded-lg bg-ink/40 px-2.5 py-2 ring-1 ring-inset ring-line/70">
            <Avatar src={r.avatar} color={SOURCE.x.color} name={r.author} size={22} />
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-1.5 text-[11px]">
                <span className="min-w-0 truncate font-medium text-neutral-300">{r.author}</span>
                {r.likes > 0 && (
                  <span className="ml-auto flex shrink-0 items-center gap-0.5 text-neutral-500">
                    <svg viewBox="0 0 24 24" width="11" height="11" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                      <path d={STAT_ICON.likes} />
                    </svg>
                    <span className="font-mono tabular">{fmtCompact(r.likes)}</span>
                  </span>
                )}
                {r.url && r.url !== "#" && (
                  <a href={r.url} target="_blank" rel="noreferrer" className={`shrink-0 text-neutral-600 transition hover:text-[#57D7BA] ${r.likes > 0 ? "" : "ml-auto"}`}>↗</a>
                )}
              </div>
              <p className="mt-0.5 whitespace-pre-line text-[12px] leading-snug text-neutral-400">{r.text}</p>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}

type LensKey =
  | "valuation" | "growth" | "competition" | "management" | "macro" | "catalyst" | "flows" | "other";
const LENSES: { k: LensKey; zh: string; en: string }[] = [
  { k: "valuation", zh: "估值", en: "Valuation" },
  { k: "growth", zh: "业务成长", en: "Growth" },
  { k: "competition", zh: "竞争", en: "Competition" },
  { k: "management", zh: "管理层", en: "Management" },
  { k: "macro", zh: "宏观", en: "Macro" },
  { k: "catalyst", zh: "催化剂", en: "Catalyst" },
  { k: "flows", zh: "资金盘面", en: "Flows" },
  { k: "other", zh: "其他", en: "Other" },
];
const LENS_LABEL: Record<string, { zh: string; en: string }> = Object.fromEntries(
  LENSES.map((l) => [l.k, { zh: l.zh, en: l.en }])
);
const PLATFORMS: KolSource[] = ["x", "youtube", "reddit", "xueqiu"];
// 时间「模板」：一键把常用区间填进起始日期（24h / 3d / 7d / 14d / 1mo）。
const WINDOWS: { k: string; days: number; zh: string; en: string }[] = [
  { k: "24h", days: 1, zh: "24 小时", en: "24h" },
  { k: "3d", days: 3, zh: "3 天", en: "3d" },
  { k: "7d", days: 7, zh: "7 天", en: "7d" },
  { k: "14d", days: 14, zh: "14 天", en: "14d" },
  { k: "1mo", days: 31, zh: "1 个月", en: "1mo" },
];
const DEFAULT_WIN_DAYS = 31; // 默认起始 = 池中最新日往前 1 个月
// 「只看高质量」不是单一分数线：YouTube 长视频基于完整口播/摘要，65 分已可读；
// 社区短帖噪声更高，必须更严格，并且要有可见正文或 AI 提炼支撑。
const QUALITY_MIN_BY_SOURCE: Record<KolSource, number> = { youtube: 65, reddit: 80, x: 80, xueqiu: 80 };
// 五种完整语言：简体中文 / 英文 / 日语 / 韩文 / 繁体中文
const LANGS: { k: string; zh: string; en: string }[] = [
  { k: "zh-Hans", zh: "简体中文", en: "简" },
  { k: "en", zh: "英文", en: "EN" },
  { k: "ja", zh: "日语", en: "JA" },
  { k: "ko", zh: "韩文", en: "KO" },
  { k: "zh-Hant", zh: "繁体中文", en: "繁" },
];
const STANCE_FILTERS: Stance[] = ["bull", "neutral", "bear"];

// 起始日期工具：day ± delta（UTC，YYYY-MM-DD）
const shiftDay = (day: string, delta: number): string => {
  if (!day) return "";
  const d = new Date(day + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + delta);
  return d.toISOString().slice(0, 10);
};

const KO_RE = /[가-힯]/;
const JA_RE = /[ぁ-ゟ゠-ヿ]/;
const HAN_RE = /[一-鿿]/;
// 繁/简 高频分歧字（启发式：数命中更多者；难分→默认简体，数据多为简体）。
const HANT_CHARS = "們這實國對學區與來為灣臺體萬沒關係點龍鳳麗東車馬鳥魚龜歲廣應該說話語讀書寫個麼樣讓會發開關閉問題經濟總統當網絡軟體資訊機構價值買賣漲跌觀認覺號";
const HANS_CHARS = "们这实国对学区与来为湾台体万没关系点龙凤丽东车马鸟鱼龟岁广应该说话语读书写个么样让会发开关闭问题经济总统当网络软件资讯机构价值买卖涨跌观认觉号";
function langOf(o: KolOpinion): string {
  const t = o.orig || o.text?.en || o.text?.zh || "";
  if (KO_RE.test(t)) return "ko";
  if (JA_RE.test(t)) return "ja";
  if (HAN_RE.test(t)) {
    let hant = 0, hans = 0;
    for (const ch of t) {
      if (HANT_CHARS.includes(ch)) hant++;
      else if (HANS_CHARS.includes(ch)) hans++;
    }
    return hant > hans ? "zh-Hant" : "zh-Hans";
  }
  return "en";
}
const lensesOf = (o: KolOpinion): LensKey[] =>
  (o.viewpoints && o.viewpoints.length ? o.viewpoints : ["other"]) as LensKey[];
const relOf = (o: KolOpinion): number => (typeof o.relevance === "number" ? o.relevance : -1);
const qualOf = (o: KolOpinion): number => (typeof o.quality === "number" ? o.quality : -1);
const hasSubstantiveText = (o: KolOpinion): boolean => {
  if (o.source === "youtube") return Boolean(o.ytSegments?.length || o.ytDigest);
  const body = (o.orig || o.text?.zh || o.text?.en || "").replace(/\s+/g, " ").trim();
  const reason = `${o.reason?.zh || ""} ${o.reason?.en || ""}`.trim();
  const points = (o.points?.zh?.length || 0) + (o.points?.en?.length || 0);
  return body.length >= 180 || reason.length >= 40 || points >= 2;
};
const isHighQuality = (o: KolOpinion): boolean =>
  qualOf(o) >= QUALITY_MIN_BY_SOURCE[o.source] && hasSubstantiveText(o);

function Chip({ active, dim, onClick, children }: { active: boolean; dim?: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      className={`rounded-md px-2 py-0.5 text-[11.5px] font-medium ring-1 ring-inset transition ${
        active ? "bg-elevated text-cream ring-[#57D7BA]" : `${dim ? "text-neutral-600" : "text-neutral-400"} ring-line hover:text-neutral-200`
      }`}
    >
      {children}
    </button>
  );
}
// 平台品牌 logo（用户提供的 PNG，web/public/platform/）：X / YouTube / Reddit / 雪球。圆角小图标。
const PLAT_LOGO: Record<KolSource, string> = {
  x: "/platform/x.png",
  youtube: "/platform/youtube.png",
  reddit: "/platform/reddit.png",
  xueqiu: "/platform/xueqiu.png",
};
function PlatformIcon({ src, size = 14 }: { src: KolSource; size?: number }) {
  return (
    <img
      src={PLAT_LOGO[src]}
      alt={SOURCE[src].label}
      width={size}
      height={size}
      style={{ width: size, height: size }}
      className="shrink-0 rounded-[3px] object-contain"
    />
  );
}

// 轻量下拉：按钮显示「标签 值 ⌄」，点开浮层；点浮层外或选项后关闭。
function Dropdown({ label, value, children }: { label: string; value: string; children: (close: () => void) => React.ReactNode }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="relative">
      <button
        onClick={() => setOpen((o) => !o)}
        className="flex h-11 min-w-[148px] items-center justify-between gap-2 rounded-md px-3.5 text-[13px] ring-1 ring-inset ring-line text-neutral-300 transition hover:text-cream"
      >
        <span className="text-neutral-500">{label}</span>
        <span className="text-cream">{value}</span>
        <svg viewBox="0 0 24 24" width="11" height="11" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" className="text-neutral-500" aria-hidden><path d="M6 9l6 6 6-6" /></svg>
      </button>
      {open && (
        <>
          <div className="fixed inset-0 z-30" onClick={() => setOpen(false)} />
          <div className="absolute left-0 z-40 mt-1 min-w-[150px] rounded-lg bg-elevated p-1 shadow-xl ring-1 ring-inset ring-line">
            {children(() => setOpen(false))}
          </div>
        </>
      )}
    </div>
  );
}
function MenuItem({ active, disabled, onClick, children }: { active?: boolean; disabled?: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-left text-[12px] transition ${
        disabled ? "cursor-default text-neutral-700" : active ? "bg-card text-[#57D7BA]" : "text-neutral-300 hover:bg-card hover:text-cream"
      }`}
    >
      {children}
    </button>
  );
}

export function OpinionExplorer({
  opinions,
  zh,
  fill = false,
  overview,
}: {
  opinions: KolOpinion[];
  zh: boolean;
  fill?: boolean;
  overview?: React.ReactNode;
}) {
  // 多选集合（空 = 不限）；时间 = 起始日期（"" 用默认 1 个月）。
  const [plat, setPlat] = useState<Set<KolSource>>(new Set());
  const [langs, setLangs] = useState<Set<string>>(new Set());
  const [stanceFilter, setStanceFilter] = useState<Set<Stance>>(new Set());
  const [since, setSince] = useState(""); // 起始日期 YYYY-MM-DD；"" = 用默认（最新日往前 1 个月）
  const [hiQ, setHiQ] = useState(false); // 「只看高质量」开关
  const [sort, setSort] = useState<"rel" | "time" | "hot">("rel"); // 排序：相关度 / 热度 / 最新
  const [query, setQuery] = useState("");
  const [showT, setShowT] = useState(false);
  const [selId, setSelId] = useState<string | null>(null);

  const toggle = <T,>(set: Set<T>, setter: (s: Set<T>) => void, v: T) => {
    const n = new Set(set);
    n.has(v) ? n.delete(v) : n.add(v);
    setter(n);
  };

  // 哪些平台/语言在池中出现（语言用于把「没有该语言」的 chip 置灰）
  const avail = useMemo(() => {
    const p = new Set<string>(), l = new Set<string>();
    for (const o of opinions) { p.add(o.source); l.add(langOf(o)); }
    return { plat: p, lang: l };
  }, [opinions]);

  // 池中日期范围（锚定到「最新发布日」，静态快照非今天 → 模板按此推算，避免空窗）
  const { minDay, maxDay } = useMemo(() => {
    let mn = "", mx = "";
    for (const o of opinions) if (o.day) { if (!mn || o.day < mn) mn = o.day; if (o.day > mx) mx = o.day; }
    return { minDay: mn, maxDay: mx };
  }, [opinions]);
  // 有效起始日：用户所选优先，否则默认最新日往前 1 个月
  const sinceEff = since || shiftDay(maxDay, -(DEFAULT_WIN_DAYS - 1));
  // 下拉按钮上显示的当前值
  const timeLabel = useMemo(() => {
    const w = WINDOWS.find((w) => shiftDay(maxDay, -(w.days - 1)) === sinceEff);
    return w ? (zh ? w.zh : w.en) : sinceEff || "—";
  }, [sinceEff, maxDay, zh]);
  const langLabel = langs.size === 0 ? (zh ? "全部" : "All") : (zh ? `${langs.size} 项` : String(langs.size));

  const baseFiltered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return opinions.filter((o) => {
      if (langs.size && !langs.has(langOf(o))) return false;
      if (stanceFilter.size && !stanceFilter.has(o.stance)) return false;
      if (sinceEff && o.day < sinceEff) return false;
      if (hiQ && !isHighQuality(o)) return false; // 「只看高质量」开关
      if (needle) {
        const haystack = [
          o.author,
          o.orig,
          o.text?.zh,
          o.text?.en,
          o.trans?.zh,
          o.trans?.en,
          o.quote?.zh,
          o.quote?.en,
          o.channel?.handle,
          o.channel?.bio,
        ].filter(Boolean).join(" ").toLowerCase();
        if (!haystack.includes(needle)) return false;
      }
      return true;
    });
  }, [opinions, langs, stanceFilter, sinceEff, hiQ, query]);

  const sourceCounts = useMemo(() => {
    const counts: Record<string, number> = {};
    for (const o of baseFiltered) counts[o.source] = (counts[o.source] ?? 0) + 1;
    return counts;
  }, [baseFiltered]);

  const filtered = useMemo(() => {
    const out = baseFiltered.filter((o) => !plat.size || plat.has(o.source));
    // 排序：相关度（降序，其次互动）/ 热度（互动降序，其次相关度）/ 最新（发布日降序，其次相关度）
    out.sort((a, b) => {
      if (sort === "time") return (a.day < b.day ? 1 : a.day > b.day ? -1 : 0) || relOf(b) - relOf(a);
      if (sort === "hot") return (b.interactions || 0) - (a.interactions || 0) || relOf(b) - relOf(a);
      return relOf(b) - relOf(a) || (b.interactions || 0) - (a.interactions || 0);
    });
    return out;
  }, [baseFiltered, plat, sort]);

  const selected = selId ? filtered.find((o) => o.id === selId) ?? null : overview ? null : filtered[0] ?? null;
  const availablePlatforms = PLATFORMS.filter((p) => avail.plat.has(p));
  const hasFilter = Boolean(query.trim() || plat.size || langs.size || stanceFilter.size || since || hiQ || sort !== "rel");
  const resetFilters = () => {
    setQuery("");
    setPlat(new Set());
    setLangs(new Set());
    setStanceFilter(new Set());
    setSince("");
    setHiQ(false);
    setSort("rel");
    setSelId(null);
    setShowT(false);
  };

  return (
    <div className={fill ? "flex h-full min-h-0 flex-col" : ""}>
      {/* Kaito 式顶部工具条：搜索 · 情绪 · 时间 · 语言 · 质量 · 清空。 */}
      <div className="flex shrink-0 items-center gap-2.5 px-0 py-0">
        <label className="relative min-w-[300px] max-w-[460px] flex-[1_1_420px]">
          <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-neutral-600">
            <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
              <circle cx="11" cy="11" r="8" />
              <path d="m21 21-4.3-4.3" />
            </svg>
          </span>
          <input
            value={query}
            onChange={(e) => { setQuery(e.target.value); setSelId(null); }}
            placeholder={zh ? "搜索主题、作者或正文" : "Search topic, author, or post"}
            className="h-11 w-full rounded-md bg-elevated/70 pl-9 pr-3 text-[13px] text-cream outline-none ring-1 ring-inset ring-line placeholder:text-neutral-600 focus:ring-reddit/70"
          />
        </label>
        <button
          type="button"
          className="h-11 min-w-[72px] shrink-0 rounded-md bg-reddit px-4 text-[13px] font-bold text-black transition hover:bg-reddit/90"
        >
          {zh ? "搜索" : "Search"}
        </button>
        <div className="inline-flex h-11 min-w-[342px] shrink-0 items-center gap-1 rounded-md bg-elevated/50 p-1 ring-1 ring-inset ring-line">
          {STANCE_FILTERS.map((key) => {
            const meta = STANCE[key];
            const active = stanceFilter.has(key);
            return (
              <button
                key={key}
                type="button"
                onClick={() => { toggle(stanceFilter, setStanceFilter, key); setSelId(null); }}
                aria-pressed={active}
                className={`inline-flex h-9 min-w-[106px] flex-1 items-center justify-center gap-1.5 rounded px-3 text-[13px] font-semibold transition ${
                  active
                    ? "border border-[#57D7BA]/80 bg-[#57D7BA]/10 text-cream shadow-[0_0_14px_rgb(87_215_186_/_0.12)] ring-1 ring-inset ring-[#57D7BA]/45"
                    : "border border-transparent text-neutral-500 hover:border-line/80 hover:text-neutral-300"
                }`}
              >
                <span className="h-1.5 w-1.5 rounded-full" style={{ background: meta.color }} />
                {zh ? meta.zh : meta.en}
              </button>
            );
          })}
        </div>
        <Dropdown label={zh ? "时间" : "Time"} value={timeLabel}>
          {(close) => (
            <div className="min-w-[150px]">
              {WINDOWS.map((w) => {
                const d = shiftDay(maxDay, -(w.days - 1));
                return (
                  <MenuItem key={w.k} active={!!d && sinceEff === d} onClick={() => { setSince(d); setSelId(null); close(); }}>
                    {zh ? w.zh : w.en}
                  </MenuItem>
                );
              })}
              <div className="my-1 border-t border-line" />
              <div className="px-2 pb-1 pt-0.5">
                <span className="text-[10px] uppercase tracking-wide text-neutral-500">{zh ? "自定义起始" : "Custom from"}</span>
                <input
                  type="date"
                  value={sinceEff}
                  min={minDay || undefined}
                  max={maxDay || undefined}
                  onChange={(e) => { setSince(e.target.value); setSelId(null); }}
                  className="mt-1 w-full rounded-md bg-card px-2 py-1 text-[11.5px] text-cream ring-1 ring-inset ring-line [color-scheme:dark]"
                />
              </div>
            </div>
          )}
        </Dropdown>
        {/* 语言：单下拉（多选） */}
        <Dropdown label={zh ? "语言" : "Lang"} value={langLabel}>
          {() => (
            <div className="min-w-[140px]">
              <MenuItem active={langs.size === 0} onClick={() => { setLangs(new Set()); setSelId(null); }}>{zh ? "全部" : "All"}</MenuItem>
              <div className="my-1 border-t border-line" />
              {LANGS.map((l) => {
                const on = langs.has(l.k);
                const dim = !avail.lang.has(l.k);
                return (
                  <MenuItem key={l.k} active={on} disabled={dim} onClick={() => { toggle(langs, setLangs, l.k); setSelId(null); }}>
                    <span className={`grid h-3 w-3 place-items-center rounded-[3px] ring-1 ring-inset ${on ? "bg-[#57D7BA] ring-[#57D7BA]" : "ring-line"}`}>
                      {on && <svg viewBox="0 0 24 24" width="9" height="9" fill="none" stroke="#0d0d0d" strokeWidth="4" strokeLinecap="round" strokeLinejoin="round" aria-hidden><path d="M5 12l5 5L20 7" /></svg>}
                    </span>
                    {zh ? l.zh : l.en}
                  </MenuItem>
                );
              })}
            </div>
          )}
        </Dropdown>
        <button
          onClick={() => { setHiQ(!hiQ); setSelId(null); }}
          className="flex h-11 min-w-[148px] shrink-0 items-center justify-center gap-2 rounded-md px-3.5 text-[13px] font-medium ring-1 ring-inset ring-line transition hover:text-neutral-200"
          title={zh ? "只展示 AI 判定为高质量(有实质分析)的帖子" : "Only AI-rated high-quality posts"}
          aria-pressed={hiQ}
        >
          <span className={`relative h-3.5 w-6 shrink-0 rounded-full transition ${hiQ ? "bg-[#57D7BA]" : "bg-elevated"}`}>
            <span className={`absolute top-[3px] h-2 w-2 rounded-full bg-white transition-all ${hiQ ? "left-[13px]" : "left-[3px]"}`} />
          </span>
          <span className={hiQ ? "text-cream" : "text-neutral-400"}>{zh ? "高质量" : "Quality"}</span>
        </button>
        <button
          type="button"
          onClick={resetFilters}
          disabled={!hasFilter}
          className="h-11 shrink-0 rounded-md px-3.5 text-[13px] font-semibold text-reddit transition hover:text-cream disabled:text-neutral-700"
        >
          {zh ? "清空" : "Clear All"}
        </button>
      </div>

      {/* 主从：左列表 / 右侧 overview 或正文。 */}
      <div className={`mt-3 flex flex-col gap-3 lg:flex-row ${fill ? "min-h-0 flex-1 overflow-hidden lg:items-stretch" : "lg:items-start"}`}>
        <div className={fill ? "flex min-h-0 flex-col overflow-hidden rounded-xl bg-card/45 ring-1 ring-inset ring-line lg:w-[392px] lg:shrink-0" : "lg:w-[320px] lg:shrink-0"}>
          <div className="shrink-0 border-b border-line">
            <div className="flex items-center gap-3 overflow-x-auto px-3 pt-3">
              <button
                type="button"
                onClick={() => { setPlat(new Set()); setSelId(null); }}
                className={`shrink-0 border-b-2 pb-2 text-[12px] font-bold transition ${plat.size === 0 ? "border-reddit text-reddit" : "border-transparent text-neutral-500 hover:text-neutral-300"}`}
              >
                {zh ? "全部" : "All"} <span className="font-mono text-[10.5px] text-neutral-600">{baseFiltered.length}</span>
              </button>
              {availablePlatforms.map((p) => {
                const on = plat.size === 1 && plat.has(p);
                return (
                  <button
                    key={p}
                    type="button"
                    onClick={() => { setPlat(new Set([p])); setSelId(null); }}
                    className={`shrink-0 border-b-2 pb-2 text-[12px] font-bold transition ${on ? "border-reddit text-reddit" : "border-transparent text-neutral-500 hover:text-neutral-300"}`}
                  >
                    {SOURCE[p].label} <span className="font-mono text-[10.5px] text-neutral-600">{sourceCounts[p] ?? 0}</span>
                  </button>
                );
              })}
            </div>
            <div className="flex items-center justify-between gap-2 px-3 py-2">
              <span className="text-[11px] text-neutral-500">{filtered.length} {zh ? "条结果" : "results"}</span>
              <div className="flex items-center gap-1">
                <span className="text-[11px] text-neutral-600">{zh ? "排序" : "Sort"}</span>
                <Chip active={sort === "rel"} onClick={() => setSort("rel")}>{zh ? "相关度" : "Rel"}</Chip>
                <Chip active={sort === "hot"} onClick={() => setSort("hot")}>{zh ? "热度" : "Top"}</Chip>
                <Chip active={sort === "time"} onClick={() => setSort("time")}>{zh ? "最新" : "New"}</Chip>
              </div>
            </div>
          </div>
          {filtered.length === 0 ? (
            <p className="py-8 text-center text-sm text-neutral-600">{zh ? "没有符合筛选的观点" : "No posts match the filters"}</p>
          ) : (
            <ul className={fill ? "min-h-0 flex-1 overflow-y-auto" : "lg:max-h-[640px] lg:overflow-y-auto"}>
              {filtered.map((o) => (
                <ListCard key={o.id} o={o} zh={zh} active={selected?.id === o.id} onClick={() => { setSelId(o.id); setShowT(false); }} />
              ))}
            </ul>
          )}
        </div>
        <div className={`min-w-0 ${fill ? "min-h-0 overflow-hidden lg:flex-1" : "lg:flex-1"}`}>
          {selected ? (
            <Reader
              o={selected}
              zh={zh}
              showT={showT}
              setShowT={setShowT}
              fill={fill}
              onBack={overview ? () => { setSelId(null); setShowT(false); } : undefined}
            />
          ) : overview ? (
            overview
          ) : null}
        </div>
      </div>
    </div>
  );
}

// 左侧列表卡（精简）：左侧 3px 色边=立场；头像 + handle + 平台 logo + 日期(灰) + 帖文开头。
// 质/相关/互动 数字移出卡面（它们是排序键、不是逐条要读的；详情在右侧阅读区）。
function ListCard({ o, zh, active, onClick }: { o: KolOpinion; zh: boolean; active: boolean; onClick: () => void }) {
  const src = SOURCE[o.source];
  const st = STANCE[o.stance];
  const { base, trans, canTranslate } = pickOriginal(o, zh);
  const preview = canTranslate ? trans : base;
  const excerpt = preview.replace(/\s+/g, " ").trim().slice(0, 84);
  return (
    <li>
      <button
        onClick={onClick}
        title={zh ? st.zh : st.en}
        className={`relative flex w-full gap-2.5 overflow-hidden border-b border-line/70 py-3 pl-4 pr-3 text-left transition ${
          active ? "bg-elevated/80" : "bg-transparent hover:bg-white/[.025]"
        }`}
      >
        <span className="absolute left-0 top-0 h-full w-[3px]" style={{ background: st.color }} aria-hidden />
        {active && <span className="absolute right-0 top-0 h-full w-[3px] bg-reddit" aria-hidden />}
        <Avatar src={o.avatar} color={src.color} name={o.author} size={26} />
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-1.5">
            <span className="min-w-0 truncate text-[12.5px] font-medium text-cream">{o.author}</span>
            <span className="ml-auto flex shrink-0 items-center gap-1.5">
              <PlatformIcon src={o.source} size={12} />
              <span className="font-mono tabular text-[10.5px] text-neutral-600">{mmdd(o.day)}</span>
            </span>
          </div>
          <p className="mt-1 line-clamp-2 text-[12px] leading-snug text-neutral-400">{excerpt}</p>
        </div>
      </button>
    </li>
  );
}

const BUCKET_LABEL: Record<"short" | "mid" | "long", { zh: string; en: string }> = {
  short: { zh: "短线", en: "short" },
  mid: { zh: "中线", en: "mid" },
  long: { zh: "长线", en: "long" },
};
const fmtPrice = (n: number) => (n >= 10 ? Math.round(n).toLocaleString() : String(+n.toFixed(2)));
const fmtRange = (lo: number, hi: number) => (hi > lo ? `$${fmtPrice(lo)}–$${fmtPrice(hi)}` : `$${fmtPrice(lo)}`);

// 正文提炼里的「作者明确给出」行：买入价位(青) / 卖出·目标价位(珊瑚) + 操作周期(原话+档)。支持区间。
// 仅在抽到(kol_judgment / yt_judgment)时出现。
function JudgmentLine({ j, zh }: { j: KolJudgment; zh: boolean }) {
  const items: { label: string; text: string; color: string }[] = [];
  if (j.buyLo != null) items.push({ label: zh ? "买入" : "Buy", text: fmtRange(j.buyLo, j.buyHi ?? j.buyLo), color: "#57D7BA" });
  if (j.sellLo != null) items.push({ label: zh ? "卖出/目标" : "Sell/target", text: fmtRange(j.sellLo, j.sellHi ?? j.sellLo), color: "#FF5C6C" });
  const horizon = j.horizon ? (zh ? j.horizon.zh : j.horizon.en) : "";
  const bk = j.bucket ? (zh ? BUCKET_LABEL[j.bucket].zh : BUCKET_LABEL[j.bucket].en) : "";
  if (!items.length && !horizon) return null;
  return (
    <div className="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1 rounded-lg bg-elevated/60 px-3 py-2 text-[12px] ring-1 ring-inset ring-line">
      <span className="text-[10px] uppercase tracking-wide text-neutral-500">{zh ? "作者明确给出" : "Stated"}</span>
      {items.map((it) => (
        <span key={it.label} className="flex items-center gap-1">
          <span className="text-neutral-500">{it.label}</span>
          <span className="font-mono tabular font-semibold" style={{ color: it.color }}>{it.text}</span>
        </span>
      ))}
      {horizon && (
        <span className="flex items-center gap-1">
          <span className="text-neutral-500">{zh ? "周期" : "Horizon"}</span>
          <span className="text-neutral-200">{horizon}{bk ? `（${bk}）` : ""}</span>
        </span>
      )}
    </div>
  );
}

// 右侧阅读面板：作者头像/handle/来源/立场/互动/相关/时间 + 完整正文 + 原文/译文切换 + 回原帖
function Reader({
  o,
  zh,
  showT,
  setShowT,
  fill = false,
  onBack,
}: {
  o: KolOpinion;
  zh: boolean;
  showT: boolean;
  setShowT: (v: boolean) => void;
  fill?: boolean;
  onBack?: () => void;
}) {
  const src = SOURCE[o.source];
  const st = STANCE[o.stance];
  const { base, trans, canTranslate } = pickOriginal(o, zh);
  const showOriginal = showT && canTranslate;
  const displayText = showOriginal ? base : (canTranslate ? trans : base);
  const hasLink = !!o.url && o.url !== "#";
  const lensKeys = lensesOf(o);
  return (
    <div
      data-reader-scroll
      className={`rounded-xl bg-card px-4 py-3.5 ring-1 ring-inset ring-line ${fill ? "h-full overflow-y-auto overflow-x-hidden" : "lg:max-h-[640px] lg:overflow-y-auto lg:overflow-x-hidden"}`}
    >
      {onBack && (
        <button
          type="button"
          onClick={onBack}
          className="mb-3 inline-flex items-center gap-1.5 text-[12px] font-medium text-neutral-400 transition hover:text-reddit"
        >
          ← {zh ? "返回概览" : "Back to overview"}
        </button>
      )}
      <div className="flex items-center gap-2.5">
        <Avatar src={o.avatar} color={src.color} name={o.author} size={34} />
        <div className="min-w-0 flex-1">
          <div className="truncate text-[14px] font-semibold text-cream">{o.author}</div>
          <div className="flex items-center gap-1.5 text-[11px]" style={{ color: src.color }}>
            <PlatformIcon src={o.source} size={12} />
            <span>{src.label} · {o.day}</span>
          </div>
          {/* YouTube 作者基础信息：粉丝数 · 视频数 · @handle */}
          {o.source === "youtube" && o.channel && (
            <div className="mt-0.5 flex flex-wrap items-center gap-x-2 text-[10.5px] text-neutral-500">
              {typeof o.channel.subscribers === "number" && o.channel.subscribers >= 0 && (
                <span><b className="font-semibold text-neutral-300">{fmtCompact(o.channel.subscribers)}</b> {zh ? "粉丝" : "subs"}</span>
              )}
              {typeof o.channel.videos === "number" && o.channel.videos > 0 && (
                <span><b className="font-semibold text-neutral-300">{fmtCompact(o.channel.videos)}</b> {zh ? "视频" : "videos"}</span>
              )}
              {o.channel.handle && <span className="truncate text-neutral-600">{o.channel.handle}</span>}
            </div>
          )}
        </div>
        <span className="shrink-0 text-[12px] font-medium" style={{ color: st.color }}>{zh ? st.zh : st.en}</span>
        {/* X 的合计数由底部互动行（赞/转/评/看/藏）呈现 → 头部不再重复 */}
        {o.source !== "x" && <span className="shrink-0 font-mono tabular text-[12px] text-neutral-500">{fmtCompact(o.interactions)}</span>}
        {typeof o.quality === "number" && (
          <span className="shrink-0 rounded bg-elevated px-1.5 py-0.5 font-mono tabular text-[11px] text-neutral-400" title={zh ? "帖子质量(含金量)" : "post quality"}>
            {zh ? "质 " : "Q "}{o.quality}
          </span>
        )}
        {typeof o.relevance === "number" && (
          <span className="shrink-0 rounded bg-elevated px-1.5 py-0.5 font-mono tabular text-[11px] text-neutral-400" title={zh ? "与本标的相关度" : "relevance to ticker"}>
            {zh ? "相关 " : "rel "}{o.relevance}
          </span>
        )}
      </div>
      {/* YouTube 作者个人简介（频道描述） */}
      {o.source === "youtube" && o.channel?.bio && (
        <p className="mt-2 line-clamp-2 whitespace-pre-line text-[11.5px] leading-snug text-neutral-500">{o.channel.bio}</p>
      )}
      {/* 视角标签 */}
      {lensKeys.length > 0 && (
        <div className="mt-2 flex flex-wrap gap-1">
          {lensKeys.slice(0, 4).map((k) => (
            <span key={k} className="rounded bg-elevated px-1.5 py-px text-[10.5px] text-neutral-400">
              {zh ? LENS_LABEL[k]?.zh : LENS_LABEL[k]?.en}
            </span>
          ))}
        </div>
      )}
      {/* 作者明确给出的 目标价 + 操作周期（kol_judgment / yt_judgment 抽取，只抽明说） */}
      {o.judgment && <JudgmentLine j={o.judgment} zh={zh} />}
      {/* YouTube 有完整内容(口播+真实关键画面帧) → 结构化渲染；其余源 = 完整正文段落 */}
      {o.source === "youtube" && o.ytSegments && o.ytSegments.length ? (
        <YtReader segments={o.ytSegments} digest={o.ytDigest} zh={zh} noCollapse />
      ) : (
        displayText && (
          <p className="mt-3 whitespace-pre-line text-[13.5px] leading-relaxed text-neutral-100">
            {displayText}
          </p>
        )
      )}
      {/* X 推文：底部互动数行（赞/转/评/看/藏） */}
      {o.source === "x" && o.metrics && <TweetStats m={o.metrics} />}
      <div className="mt-3 flex items-center gap-3 text-[11.5px]">
        {canTranslate && (
          <button onClick={() => setShowT(!showT)} className="text-neutral-500 transition hover:text-[#57D7BA]">
            {showOriginal ? (zh ? "看译文" : "Translation") : (zh ? "看原文" : "Original")}
          </button>
        )}
        {hasLink && (
          <a href={o.url} target="_blank" rel="noreferrer" className="text-neutral-500 transition hover:text-[#57D7BA]">
            {zh ? "查看原帖 ↗" : "View original ↗"}
          </a>
        )}
      </div>
      {/* X 推文：帖文下的高互动评论 */}
      {o.source === "x" && o.replies && <TweetReplies replies={o.replies} zh={zh} />}
    </div>
  );
}
