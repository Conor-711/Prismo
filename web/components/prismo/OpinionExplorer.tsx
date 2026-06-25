"use client";

// 标的页「个体观点 · KOL」的观点浏览器（替代原 按KOL/按视角/按热度 三 tab）：
//   顶部 = 筛选条（平台 / 立场 / 视角 / 时间 / 语言 / 相关性）
//   下方 = 主从布局：左窄列 = 帖文卡列表（头像+handle+开头），右宽栏 = 选中帖的完整原文（含「译」+回原帖）
// 全部筛选在前端做；默认按「相关性」降序排（最相关的在前）。数据来自 lib/kolQueries.getKolOpinions（近 ~30 天扁平池）。
import { useMemo, useState } from "react";
import type { KolOpinion, KolSource, Stance } from "@/lib/mockDetail";
import { Avatar, SOURCE, STANCE, pickOriginal, mmdd } from "./kolShared";
import { fmtCompact } from "@/lib/format";

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
const STANCES: Stance[] = ["bull", "bear", "neutral"];
const WINDOWS: { k: string; days: number; zh: string; en: string }[] = [
  { k: "24h", days: 1, zh: "24 小时", en: "24h" },
  { k: "3d", days: 3, zh: "3 天", en: "3d" },
  { k: "7d", days: 7, zh: "7 天", en: "7d" },
  { k: "14d", days: 14, zh: "14 天", en: "14d" },
  { k: "1mo", days: 31, zh: "1 个月", en: "1mo" },
];
const QUALITY_MIN = 65; // 「只看高质量」阈值：kol_quality ≥ 此分算高质量（=「言之有物」及以上）
const LANGS: { k: string; zh: string; en: string }[] = [
  { k: "zh", zh: "中文", en: "中" },
  { k: "en", zh: "英文", en: "EN" },
  { k: "ja", zh: "日文", en: "JA" },
  { k: "ko", zh: "韩文", en: "KO" },
];

const KO_RE = /[가-힯]/;
const JA_RE = /[ぁ-ゟ゠-ヿ]/;
const HAN_RE = /[一-鿿]/;
function langOf(o: KolOpinion): string {
  const t = o.orig || o.text?.en || o.text?.zh || "";
  if (KO_RE.test(t)) return "ko";
  if (JA_RE.test(t)) return "ja";
  if (HAN_RE.test(t)) return "zh";
  return "en";
}
const lensesOf = (o: KolOpinion): LensKey[] =>
  (o.viewpoints && o.viewpoints.length ? o.viewpoints : ["other"]) as LensKey[];
const relOf = (o: KolOpinion): number => (typeof o.relevance === "number" ? o.relevance : -1);
const qualOf = (o: KolOpinion): number => (typeof o.quality === "number" ? o.quality : -1);

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
function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-wrap items-center gap-1.5">
      <span className="w-10 shrink-0 text-[11px] text-neutral-500">{label}</span>
      {children}
    </div>
  );
}

export function OpinionExplorer({ opinions, zh }: { opinions: KolOpinion[]; zh: boolean }) {
  // 多选集合（空 = 不限）；时间/相关性 单选。
  const [plat, setPlat] = useState<Set<KolSource>>(new Set());
  const [stance, setStance] = useState<Set<Stance>>(new Set());
  const [lens, setLens] = useState<Set<LensKey>>(new Set());
  const [langs, setLangs] = useState<Set<string>>(new Set());
  const [win, setWin] = useState("1mo");
  const [hiQ, setHiQ] = useState(false); // 「只看高质量」开关
  const [sort, setSort] = useState<"rel" | "time">("rel"); // 排序：相关度 / 最新
  const [showT, setShowT] = useState(false);
  const [selId, setSelId] = useState<string | null>(null);

  const toggle = <T,>(set: Set<T>, setter: (s: Set<T>) => void, v: T) => {
    const n = new Set(set);
    n.has(v) ? n.delete(v) : n.add(v);
    setter(n);
  };

  // 哪些平台/语言在池中出现 → 只渲染存在的 chip
  const avail = useMemo(() => {
    const p = new Set<string>(), l = new Set<string>();
    for (const o of opinions) { p.add(o.source); l.add(langOf(o)); }
    return { plat: p, lang: l };
  }, [opinions]);

  // 时间窗锚定到「池中最新发布日」（静态快照可能不是今天），avoids 空窗
  const maxDay = useMemo(() => opinions.reduce((m, o) => (o.day > m ? o.day : m), ""), [opinions]);
  const winCutoff = useMemo(() => {
    const w = WINDOWS.find((x) => x.k === win);
    if (!w || !maxDay) return "";
    const d = new Date(maxDay + "T00:00:00Z");
    d.setUTCDate(d.getUTCDate() - (w.days - 1));
    return d.toISOString().slice(0, 10);
  }, [win, maxDay]);
  const filtered = useMemo(() => {
    const out = opinions.filter((o) => {
      if (plat.size && !plat.has(o.source)) return false;
      if (stance.size && !stance.has(o.stance)) return false;
      if (lens.size && !lensesOf(o).some((k) => lens.has(k))) return false;
      if (langs.size && !langs.has(langOf(o))) return false;
      if (winCutoff && o.day < winCutoff) return false;
      if (hiQ && qualOf(o) < QUALITY_MIN) return false; // 「只看高质量」开关
      return true;
    });
    // 排序：相关度（降序，其次互动）/ 最新（发布日降序，其次相关度）
    out.sort((a, b) =>
      sort === "time"
        ? (a.day < b.day ? 1 : a.day > b.day ? -1 : 0) || relOf(b) - relOf(a)
        : relOf(b) - relOf(a) || b.interactions - a.interactions
    );
    return out;
  }, [opinions, plat, stance, lens, langs, winCutoff, hiQ, sort]);

  const selected = filtered.find((o) => o.id === selId) || filtered[0] || null;

  return (
    <div>
      {/* 筛选条 */}
      <div className="space-y-1.5 rounded-lg bg-card/50 p-2.5 ring-1 ring-inset ring-line">
        <Row label={zh ? "平台" : "Src"}>
          {PLATFORMS.filter((p) => avail.plat.has(p)).map((p) => (
            <Chip key={p} active={plat.has(p)} onClick={() => toggle(plat, setPlat, p)}>
              <span style={{ color: SOURCE[p].color }}>●</span> {SOURCE[p].label}
            </Chip>
          ))}
        </Row>
        <Row label={zh ? "立场" : "View"}>
          {STANCES.map((s) => (
            <Chip key={s} active={stance.has(s)} onClick={() => toggle(stance, setStance, s)}>
              <span style={{ color: STANCE[s].color }}>{zh ? STANCE[s].zh : STANCE[s].en}</span>
            </Chip>
          ))}
        </Row>
        <Row label={zh ? "视角" : "Lens"}>
          {LENSES.map((l) => (
            <Chip key={l.k} active={lens.has(l.k)} onClick={() => toggle(lens, setLens, l.k)}>
              {zh ? l.zh : l.en}
            </Chip>
          ))}
        </Row>
        <Row label={zh ? "时间" : "Time"}>
          {WINDOWS.map((w) => (
            <Chip key={w.k} active={win === w.k} onClick={() => setWin(w.k)}>{zh ? w.zh : w.en}</Chip>
          ))}
        </Row>
        {avail.lang.size > 1 && (
          <Row label={zh ? "语言" : "Lang"}>
            {LANGS.filter((l) => avail.lang.has(l.k)).map((l) => (
              <Chip key={l.k} active={langs.has(l.k)} onClick={() => toggle(langs, setLangs, l.k)}>
                {zh ? l.zh : l.en}
              </Chip>
            ))}
          </Row>
        )}
        <Row label={zh ? "质量" : "Qual"}>
          <button
            onClick={() => setHiQ(!hiQ)}
            className="flex items-center gap-1.5 rounded-md px-2 py-0.5 text-[11.5px] font-medium ring-1 ring-inset ring-line transition hover:text-neutral-200"
            title={zh ? "只展示 AI 判定为高质量(有实质分析)的帖子" : "Only AI-rated high-quality posts"}
          >
            <span className={`relative h-3.5 w-6 shrink-0 rounded-full transition ${hiQ ? "bg-[#57D7BA]" : "bg-elevated"}`}>
              <span className={`absolute top-[3px] h-2 w-2 rounded-full bg-white transition-all ${hiQ ? "left-[13px]" : "left-[3px]"}`} />
            </span>
            <span className={hiQ ? "text-cream" : "text-neutral-400"}>{zh ? "只看高质量" : "High quality only"}</span>
          </button>
        </Row>
      </div>

      {/* 主从：左列表 / 右阅读 */}
      <div className="mt-3 flex flex-col gap-3 lg:flex-row">
        <div className="lg:w-[36%] lg:shrink-0">
          <div className="mb-1.5 flex items-center gap-1.5">
            <span className="text-[11px] text-neutral-500">{filtered.length} {zh ? "条" : "posts"}</span>
            <span className="ml-auto text-[11px] text-neutral-600">{zh ? "排序" : "Sort"}</span>
            <Chip active={sort === "rel"} onClick={() => setSort("rel")}>{zh ? "相关度" : "Relevance"}</Chip>
            <Chip active={sort === "time"} onClick={() => setSort("time")}>{zh ? "最新" : "Newest"}</Chip>
          </div>
          {filtered.length === 0 ? (
            <p className="py-8 text-center text-sm text-neutral-600">{zh ? "没有符合筛选的观点" : "No posts match the filters"}</p>
          ) : (
            <ul className="space-y-1.5 lg:max-h-[620px] lg:overflow-y-auto lg:pr-1">
              {filtered.map((o) => (
                <ListCard key={o.id} o={o} zh={zh} active={selected?.id === o.id} onClick={() => { setSelId(o.id); setShowT(false); }} />
              ))}
            </ul>
          )}
        </div>
        <div className="min-w-0 lg:flex-1">
          {selected ? <Reader o={selected} zh={zh} showT={showT} setShowT={setShowT} /> : null}
        </div>
      </div>
    </div>
  );
}

// 左侧列表卡：头像 + handle + 立场 + 相关分 + 帖文开头
function ListCard({ o, zh, active, onClick }: { o: KolOpinion; zh: boolean; active: boolean; onClick: () => void }) {
  const src = SOURCE[o.source];
  const st = STANCE[o.stance];
  const { base } = pickOriginal(o, zh);
  const excerpt = base.replace(/\s+/g, " ").trim().slice(0, 84);
  return (
    <li>
      <button
        onClick={onClick}
        className={`flex w-full gap-2.5 rounded-lg px-3 py-2.5 text-left ring-1 ring-inset transition ${
          active ? "bg-elevated ring-[#57D7BA]" : "bg-card/60 ring-line hover:bg-card"
        }`}
      >
        <Avatar src={o.avatar} color={src.color} name={o.author} size={26} />
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-1.5">
            <span className="min-w-0 truncate text-[12.5px] font-medium text-cream">{o.author}</span>
            <span className="ml-auto shrink-0 text-[10px]" style={{ color: src.color }}>{src.label}</span>
          </div>
          <div className="mt-0.5 flex items-center gap-1.5 text-[10.5px]">
            <span style={{ color: st.color }}>{zh ? st.zh : st.en}</span>
            <span className="font-mono tabular text-neutral-600">{fmtCompact(o.interactions)}</span>
            <span className="font-mono tabular text-neutral-600">{mmdd(o.day)}</span>
            <span className="ml-auto flex shrink-0 items-center gap-1">
              {typeof o.quality === "number" && (
                <span className="rounded bg-elevated px-1 font-mono tabular text-[10px] text-neutral-400" title={zh ? "帖子质量" : "quality"}>
                  {zh ? "质 " : "Q "}{o.quality}
                </span>
              )}
              {typeof o.relevance === "number" && (
                <span className="rounded bg-elevated px-1 font-mono tabular text-[10px] text-neutral-400" title={zh ? "相关度" : "relevance"}>
                  {zh ? "相关 " : "rel "}{o.relevance}
                </span>
              )}
            </span>
          </div>
          <p className="mt-1 line-clamp-2 text-[12px] leading-snug text-neutral-400">{excerpt}</p>
        </div>
      </button>
    </li>
  );
}

// 右侧阅读面板：作者头像/handle/来源/立场/互动/相关/时间 + 完整原文 + 「译」 + 回原帖
function Reader({ o, zh, showT, setShowT }: { o: KolOpinion; zh: boolean; showT: boolean; setShowT: (v: boolean) => void }) {
  const src = SOURCE[o.source];
  const st = STANCE[o.stance];
  const { base, trans, canTranslate } = pickOriginal(o, zh);
  const showTrans = showT && canTranslate;
  const hasLink = !!o.url && o.url !== "#";
  const lensKeys = lensesOf(o);
  return (
    <div className="rounded-xl bg-card px-4 py-3.5 ring-1 ring-inset ring-line">
      <div className="flex items-center gap-2.5">
        <Avatar src={o.avatar} color={src.color} name={o.author} size={34} />
        <div className="min-w-0 flex-1">
          <div className="truncate text-[14px] font-semibold text-cream">{o.author}</div>
          <div className="text-[11px]" style={{ color: src.color }}>{src.label} · {o.day}</div>
        </div>
        <span className="shrink-0 text-[12px] font-medium" style={{ color: st.color }}>{zh ? st.zh : st.en}</span>
        <span className="shrink-0 font-mono tabular text-[12px] text-neutral-500">{fmtCompact(o.interactions)}</span>
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
      {(showTrans ? trans : base) && (
        <p className={`mt-3 whitespace-pre-line text-[13.5px] leading-relaxed ${showTrans ? "italic text-neutral-300" : "text-neutral-100"}`}>
          {showTrans ? trans : base}
        </p>
      )}
      <div className="mt-3 flex items-center gap-3 text-[11.5px]">
        {canTranslate && (
          <button onClick={() => setShowT(!showT)} className="text-neutral-500 transition hover:text-[#57D7BA]">
            {showT ? (zh ? "看原文" : "Original") : (zh ? "译" : "Translate")}
          </button>
        )}
        {hasLink && (
          <a href={o.url} target="_blank" rel="noreferrer" className="text-neutral-500 transition hover:text-[#57D7BA]">
            {zh ? "查看原帖 ↗" : "View original ↗"}
          </a>
        )}
      </div>
    </div>
  );
}
