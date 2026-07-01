"use client";

// 折线K线图下方的「分类区」：把 KOL 观点按三种方式组织——
//   · KOL：按作者（大V）分组，看「谁说了什么」（用选定时间区间的观点）。
//   · 视角：**原帖流**——每条视角下分 看多/中性/看空；AI（kol_argument）只做「分组」：
//          claim 当路标、supporters 当一簇，正文展示**原帖原文**（头像+原文+互动+回原帖），
//          不再展示 AI 编织的叙事正文（顶部只留一行 lead 当图例）。无数据时回退旧观点卡。
//   · 热度：按互动量排序的平铺列表（用选定时间区间的观点）。
import { useMemo, useState } from "react";
import type { KolOpinion, KolSource, Stance } from "@/lib/mockDetail";
import type { KolArguments, WindowedArguments, StanceGroup, KolArgument, ArgSupporter, LensKey as ArgLens } from "@/lib/kolQueries";
import { Avatar, OpinionCard, SOURCE, STANCE, pickOriginal } from "./kolShared";
import { fmtCompact } from "@/lib/format";

type Mode = "lens" | "kol" | "heat";
const TABS: { k: Mode; zh: string; en: string }[] = [
  { k: "kol", zh: "按 KOL", en: "By KOL" },
  { k: "lens", zh: "按视角", en: "By lens" },
  { k: "heat", zh: "按热度", en: "By heat" },
];
// 「按视角」论点的时间窗（各窗独立预烤的论点/叙事）
const WINDOW_OPTS: { k: string; zh: string; en: string }[] = [
  { k: "24h", zh: "24 小时", en: "24h" },
  { k: "3d", zh: "3 天", en: "3d" },
  { k: "7d", zh: "7 天", en: "7d" },
  { k: "14d", zh: "14 天", en: "14d" },
  { k: "1mo", zh: "1 个月", en: "1mo" },
];

type LensKey =
  | "valuation" | "growth" | "competition" | "management" | "macro" | "catalyst" | "flows" | "other";
interface Lens { key: LensKey; accent: string; zh: string; en: string; qzh: string; qen: string }
const LENSES: Lens[] = [
  { key: "valuation", accent: "#57D7BA", zh: "估值", en: "Valuation", qzh: "贵还是便宜", qen: "Cheap or expensive?" },
  { key: "growth", accent: "#6FBF8F", zh: "业务与成长", en: "Business & growth", qzh: "生意好不好、还能不能长", qen: "Good business, can it grow?" },
  { key: "competition", accent: "#E0A33E", zh: "竞争格局", en: "Competition", qzh: "打得过对手吗", qen: "Can it beat rivals?" },
  { key: "management", accent: "#8FB3C4", zh: "管理层", en: "Management", qzh: "管事的人靠谱吗", qen: "Is management trustworthy?" },
  { key: "macro", accent: "#C4A35B", zh: "宏观与政策", en: "Macro & policy", qzh: "大环境顺不顺", qen: "Is the environment favorable?" },
  { key: "catalyst", accent: "#E07A55", zh: "催化剂", en: "Catalysts", qzh: "近期什么会引爆", qen: "What ignites it soon?" },
  { key: "flows", accent: "#5BA3C4", zh: "资金与盘面", en: "Capital & flows", qzh: "钱和人气怎么走", qen: "How money & sentiment move?" },
];
const OTHER: Lens = { key: "other", accent: "#7A8A96", zh: "其他", en: "Other", qzh: "方向性 / 情绪，未归入上述视角", qen: "Directional / sentiment, no specific lens" };
const ALL_LENS = [...LENSES, OTHER];
const LMAP: Record<string, Lens> = Object.fromEntries(ALL_LENS.map((L) => [L.key, L]));

const CAP = 8; // 选中视角 / 热度列表初始展示条数

function Empty({ zh }: { zh: boolean }) {
  return <p className="py-6 text-center text-sm text-neutral-600">{zh ? "该区间暂无 KOL 观点" : "No KOL opinions in this range"}</p>;
}

function StanceMini({ items }: { items: KolOpinion[] }) {
  const b = items.filter((o) => o.stance === "bull").length;
  const e = items.filter((o) => o.stance === "bear").length;
  const tot = Math.max(1, items.length);
  const ne = items.length - b - e;
  return (
    <div className="flex h-1 w-full overflow-hidden rounded-full bg-elevated">
      <span style={{ width: `${(b / tot) * 100}%`, background: STANCE.bull.color }} />
      <span style={{ width: `${(ne / tot) * 100}%`, background: "#3a3d3f" }} />
      <span style={{ width: `${(e / tot) * 100}%`, background: STANCE.bear.color }} />
    </div>
  );
}

export function ClassifiedOpinions({ opinions, args, zh }: { opinions: KolOpinion[]; args?: WindowedArguments; zh: boolean }) {
  const [mode, setMode] = useState<Mode>("lens");
  const [win, setWin] = useState("14d"); // 论点时间窗（默认 14 天，数据最厚）
  const [lensSel, setLensSel] = useState<LensKey | null>(null);
  const [expandLens, setExpandLens] = useState(false);
  const [expandHeat, setExpandHeat] = useState(false);

  const anyArgs = !!args && Object.keys(args).length > 0; // 该标的有无任何窗口的论点
  const winArgs = args?.[win]; // 选定窗口的论点
  const hasArgs = useMemo(
    () => !!winArgs && LENSES.some((L) => {
      const g = winArgs[L.key as ArgLens];
      return !!g && (g.bull.args.length > 0 || g.neutral.args.length > 0 || g.bear.args.length > 0);
    }),
    [winArgs]
  );

  const byHeat = useMemo(() => [...opinions].sort((a, b) => b.interactions - a.interactions), [opinions]);

  const byLens = useMemo(() => {
    const g = new Map<LensKey, KolOpinion[]>();
    for (const o of opinions) {
      const vps = (o.viewpoints && o.viewpoints.length ? o.viewpoints : ["other"]) as LensKey[];
      const seen = new Set<LensKey>();
      for (const k of vps) {
        if (seen.has(k)) continue;
        seen.add(k);
        if (!g.has(k)) g.set(k, []);
        g.get(k)!.push(o);
      }
    }
    for (const arr of g.values()) arr.sort((a, b) => b.interactions - a.interactions);
    return g;
  }, [opinions]);

  const topLens = useMemo<LensKey | null>(() => {
    let best: LensKey | null = null, bestN = 0;
    for (const L of LENSES) {
      const c = (byLens.get(L.key) || []).length;
      if (c > bestN) { bestN = c; best = L.key; }
    }
    if (!best && (byLens.get("other") || []).length) best = "other";
    return best;
  }, [byLens]);
  const effSel: LensKey | null = lensSel && (byLens.get(lensSel) || []).length ? lensSel : topLens;

  const byKol = useMemo(() => {
    const m = new Map<string, { author: string; source: KolSource; avatar?: string; ops: KolOpinion[]; total: number }>();
    for (const o of opinions) {
      const key = `${o.source}:${o.author}`;
      let g = m.get(key);
      if (!g) { g = { author: o.author, source: o.source, avatar: o.avatar, ops: [], total: 0 }; m.set(key, g); }
      g.ops.push(o);
      g.total += o.interactions;
    }
    const arr = [...m.values()];
    for (const g of arr) g.ops.sort((a, b) => b.interactions - a.interactions);
    arr.sort((a, b) => b.total - a.total);
    return arr;
  }, [opinions]);

  return (
    <div>
      {/* 分类方式 tab */}
      <div className="mb-3 inline-flex rounded-lg bg-card p-0.5 ring-1 ring-inset ring-line">
        {TABS.map((t) => (
          <button
            key={t.k}
            onClick={() => setMode(t.k)}
            className={`rounded-md px-3 py-1 text-[12.5px] font-medium transition ${
              mode === t.k ? "bg-elevated text-cream" : "text-neutral-500 hover:text-neutral-300"
            }`}
          >
            {zh ? t.zh : t.en}
          </button>
        ))}
      </div>

      {mode === "lens" ? (
        // 视角：论点视图（与时间轴解耦，按时间窗切换）；无任何窗口论点则回退观点分组
        anyArgs ? (
          <>
            <div className="mb-3 inline-flex flex-wrap rounded-lg bg-card p-0.5 ring-1 ring-inset ring-line">
              {WINDOW_OPTS.map((w) => (
                <button
                  key={w.k}
                  onClick={() => setWin(w.k)}
                  className={`rounded-md px-2.5 py-1 text-[11.5px] font-medium transition ${
                    win === w.k ? "bg-elevated text-cream" : "text-neutral-500 hover:text-neutral-300"
                  }`}
                >
                  {zh ? w.zh : w.en}
                </button>
              ))}
            </div>
            {hasArgs && winArgs ? (
              <ArgLensView args={winArgs} zh={zh} />
            ) : (
              <p className="py-6 text-center text-sm text-neutral-600">{zh ? "该时间窗暂无论点" : "No arguments in this window"}</p>
            )}
          </>
        ) : opinions.length ? (
          <LensView byLens={byLens} effSel={effSel} setLensSel={setLensSel} expand={expandLens} setExpand={setExpandLens} zh={zh} />
        ) : (
          <Empty zh={zh} />
        )
      ) : opinions.length === 0 ? (
        <Empty zh={zh} />
      ) : mode === "heat" ? (
        <>
          <ul className="grid gap-2.5 sm:grid-cols-2">
            {(expandHeat ? byHeat : byHeat.slice(0, CAP * 2)).map((o) => <OpinionCard key={o.id} o={o} zh={zh} />)}
          </ul>
          {byHeat.length > CAP * 2 && (
            <button onClick={() => setExpandHeat((v) => !v)} className="mt-2.5 text-[12px] font-medium text-neutral-500 hover:text-cream">
              {expandHeat ? (zh ? "收起" : "Show less") : zh ? `展开全部 ${byHeat.length} 条` : `Show all ${byHeat.length}`}
            </button>
          )}
        </>
      ) : (
        <div className="space-y-2.5">
          {byKol.map((g) => (
            <section key={`${g.source}:${g.author}`} className="rounded-xl bg-card/60 p-3 ring-1 ring-inset ring-line">
              <div className="mb-2 flex items-center gap-2.5">
                <Avatar src={g.avatar} color={SOURCE[g.source].color} name={g.author} />
                <div className="min-w-0">
                  <div className="truncate text-[13.5px] font-semibold text-cream">{g.author}</div>
                  <div className="text-[11px]" style={{ color: SOURCE[g.source].color }}>{SOURCE[g.source].label}</div>
                </div>
                <span className="ml-auto flex shrink-0 items-center gap-2 text-[11.5px] text-neutral-500">
                  <span>{g.ops.length} {zh ? "条" : ""}</span>
                  <span className="font-mono tabular">{fmtCompact(g.total)}</span>
                </span>
              </div>
              <ul className="grid gap-2.5 sm:grid-cols-2">
                {g.ops.map((o) => <OpinionCard key={o.id} o={o} zh={zh} compact />)}
              </ul>
            </section>
          ))}
        </div>
      )}
    </div>
  );
}

// ===================== 论点视图（kol_argument）=====================
const ARG_STANCES: Stance[] = ["bull", "neutral", "bear"];

function ArgLensView({ args, zh }: { args: KolArguments; zh: boolean }) {
  const [sel, setSel] = useState<LensKey | null>(null);

  // 各视角聚合：按支持人数算多空分布 + 总人数（驱动紧凑网格）
  const agg = useMemo(() => {
    const m = new Map<LensKey, { total: number; bull: number; neutral: number; bear: number; n: number }>();
    const sum = (sg?: StanceGroup) => (sg?.args || []).reduce((s, a) => s + a.supportCount, 0);
    for (const L of LENSES) {
      const g = args[L.key as ArgLens];
      const n = g ? g.bull.args.length + g.neutral.args.length + g.bear.args.length : 0;
      m.set(L.key, { total: sum(g?.bull) + sum(g?.neutral) + sum(g?.bear), bull: sum(g?.bull), neutral: sum(g?.neutral), bear: sum(g?.bear), n });
    }
    return m;
  }, [args]);

  const topLens = useMemo<LensKey | null>(() => {
    let best: LensKey | null = null, bestN = 0;
    for (const L of LENSES) {
      const t = agg.get(L.key)?.total || 0;
      if (t > bestN) { bestN = t; best = L.key; }
    }
    return best;
  }, [agg]);
  const eff = sel && (agg.get(sel)?.n || 0) ? sel : topLens;
  const selLens = eff ? LMAP[eff] : null;
  const g = eff ? args[eff as ArgLens] : undefined;

  return (
    <div>
      {/* 紧凑视角网格：一屏看全 7 视角分布（人数 + 多空小条），空视角弱化不可点 */}
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        {LENSES.map((L) => {
          const a = agg.get(L.key)!;
          const on = a.n > 0;
          const isSel = eff === L.key;
          const tot = Math.max(1, a.bull + a.neutral + a.bear);
          return (
            <button
              key={L.key}
              disabled={!on}
              title={zh ? L.qzh : L.qen}
              onClick={() => on && setSel(L.key)}
              className={`flex flex-col gap-1.5 rounded-lg px-2.5 py-2 text-left ring-1 ring-inset transition ${
                !on ? "cursor-default opacity-40 ring-line/40" : isSel ? "bg-elevated ring-2 ring-[#57D7BA]" : "ring-line hover:bg-card"
              }`}
            >
              <div className="flex items-center gap-1.5">
                <span className="h-2 w-2 shrink-0 rounded-full" style={{ background: L.accent }} />
                <span className="truncate text-[12.5px] font-semibold text-cream">{zh ? L.zh : L.en}</span>
                <span className="ml-auto font-mono tabular text-[12px] text-neutral-400">{a.total || ""}</span>
              </div>
              <div className="flex h-1 w-full overflow-hidden rounded-full bg-elevated">
                <span style={{ width: `${(a.bull / tot) * 100}%`, background: STANCE.bull.color }} />
                <span style={{ width: `${(a.neutral / tot) * 100}%`, background: "#3a3d3f" }} />
                <span style={{ width: `${(a.bear / tot) * 100}%`, background: STANCE.bear.color }} />
              </div>
            </button>
          );
        })}
      </div>

      {/* 选中视角：看多 / 中性 / 看空 三列论点 */}
      {selLens && g && (
        <div className="mt-3">
          <div className="mb-2 flex items-baseline gap-2">
            <span className="h-4 w-1 rounded-full" style={{ background: selLens.accent }} />
            <h4 className="font-display text-[14px] font-bold text-cream">{zh ? selLens.zh : selLens.en}</h4>
            <span className="truncate text-[11.5px] text-neutral-500">{zh ? selLens.qzh : selLens.qen}</span>
          </div>
          <div className="space-y-3">
            {ARG_STANCES.map((st) => (
              <StanceSection key={st} stance={st} grp={st === "bull" ? g.bull : st === "bear" ? g.bear : g.neutral} zh={zh} />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

// 立场区块（方案A）：一行图例（叙事 lead，可选）+ 若干「论点簇」。每簇 = 路标(AI claim) + 原帖卡。
function StanceSection({ stance, grp, zh }: { stance: Stance; grp: StanceGroup; zh: boolean }) {
  const sc = STANCE[stance];
  const clusters = grp.args.filter((a) => a.supporters.length > 0);
  const lead = grp.narrative?.lead ? (zh ? grp.narrative.lead.zh : grp.narrative.lead.en) : "";
  if (!clusters.length && !lead) return null;
  const people = clusters.reduce((n, a) => n + a.supporters.length, 0);
  return (
    <section className="rounded-lg bg-card/40 p-3.5 ring-1 ring-inset ring-line">
      <div className="flex items-center gap-1.5 text-[12.5px] font-semibold" style={{ color: sc.color }}>
        <span className="h-2.5 w-2.5 rounded-full" style={{ background: sc.color }} />
        {zh ? sc.zh : sc.en}
        <span className="font-mono tabular text-neutral-600">{people || ""}</span>
      </div>
      {/* 图例：一句话定位，不替代原帖（方案A 顶部一行概览） */}
      {lead && <p className="mt-1.5 text-[12px] leading-relaxed text-neutral-500">{lead}</p>}
      {clusters.length > 0 && (
        <div className="mt-3 space-y-3.5">
          {clusters.map((c, i) => <Cluster key={i} c={c} color={sc.color} zh={zh} />)}
        </div>
      )}
    </section>
  );
}

// 论点簇：路标（AI 一句话主张，仅作索引）+ 持此观点者的原帖卡。默认显示浮现分最高的 2 条，余下可展开。
function Cluster({ c, color, zh }: { c: KolArgument; color: string; zh: boolean }) {
  const [open, setOpen] = useState(false);
  const claim = zh ? c.claim.zh : c.claim.en;
  const sups = c.supporters;
  const shown = open ? sups : sups.slice(0, 2);
  const more = sups.length - 2;
  return (
    <div>
      {claim && (
        <div className="mb-1.5 flex items-baseline gap-2">
          <span className="mt-[6px] h-1.5 w-1.5 shrink-0 self-start rounded-full" style={{ background: color, opacity: 0.85 }} />
          <span className="text-[13px] font-semibold leading-snug text-cream">{claim}</span>
          <span className="ml-auto shrink-0 font-mono tabular text-[11px] text-neutral-500">{sups.length}</span>
        </div>
      )}
      <ul className="space-y-2">
        {shown.map((s, j) => <OriginalCard key={j} s={s} zh={zh} />)}
      </ul>
      {more > 0 && (
        <button onClick={() => setOpen((v) => !v)} className="mt-2 text-[11.5px] font-medium text-neutral-500 transition hover:text-cream">
          {open ? (zh ? "收起" : "Show less") : zh ? `+ 还有 ${more} 人持相同观点` : `+ ${more} more with this view`}
        </button>
      )}
    </div>
  );
}

// 原帖卡：作者身份（头像+来源）+ 立场 + 互动 + 帖子正文 + 翻译/原文切换 + 回原帖。
// 默认展示界面语言；原文异语种且有忠实译文时给「看原文」切换。
function OriginalCard({ s, zh }: { s: ArgSupporter; zh: boolean }) {
  const [showT, setShowT] = useState(false);
  const src = SOURCE[s.source];
  const st = STANCE[s.stance];
  const { base, trans, canTranslate: canT } = pickOriginal(s, zh);
  const showOriginal = showT && canT;
  const displayText = showOriginal ? base : (canT ? trans : base);
  const hasLink = !!s.url && s.url !== "#";
  return (
    <li className="rounded-lg bg-card px-3.5 py-2.5 ring-1 ring-inset ring-line">
      <div className="flex items-center gap-2.5">
        <Avatar src={s.avatar} color={src.color} name={s.author} size={26} />
        <div className="min-w-0 flex-1 leading-tight">
          <div className="truncate text-[12.5px] font-medium text-cream">{s.author}</div>
          <div className="text-[10.5px]" style={{ color: src.color }}>{src.label}</div>
        </div>
        <span className="shrink-0 text-[11px] font-medium" style={{ color: st.color }}>{zh ? st.zh : st.en}</span>
        <span className="shrink-0 font-mono tabular text-[11px] text-neutral-500">{fmtCompact(s.interactions)}</span>
      </div>
      {displayText && (
        <p className="mt-2 whitespace-pre-line text-[13px] leading-relaxed text-neutral-200">
          {displayText}
        </p>
      )}
      {(canT || hasLink) && (
        <div className="mt-1.5 flex items-center gap-3 text-[11px]">
          {canT && (
            <button onClick={() => setShowT((v) => !v)} className="text-neutral-500 transition hover:text-[#57D7BA]">
              {showOriginal ? (zh ? "看译文" : "Translation") : (zh ? "看原文" : "Original")}
            </button>
          )}
          {hasLink && (
            <a href={s.url} target="_blank" rel="noreferrer" className="text-neutral-500 transition hover:text-[#57D7BA]">
              {zh ? "查看原帖 ↗" : "View original ↗"}
            </a>
          )}
        </div>
      )}
    </li>
  );
}

// ===================== 旧：按视角分组的观点卡（无 kol_argument 时回退）=====================
function LensView({
  byLens, effSel, setLensSel, expand, setExpand, zh,
}: {
  byLens: Map<LensKey, KolOpinion[]>;
  effSel: LensKey | null;
  setLensSel: (k: LensKey) => void;
  expand: boolean;
  setExpand: (f: (v: boolean) => boolean) => void;
  zh: boolean;
}) {
  const selItems = effSel ? byLens.get(effSel) || [] : [];
  const selLens = effSel ? LMAP[effSel] : null;
  const shown = expand ? selItems : selItems.slice(0, CAP);
  return (
    <div>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        {ALL_LENS.map((L) => {
          const items = byLens.get(L.key) || [];
          const on = items.length > 0;
          const sel = effSel === L.key;
          return (
            <button
              key={L.key}
              disabled={!on}
              title={zh ? L.qzh : L.qen}
              onClick={() => on && setLensSel(L.key)}
              className={`flex flex-col gap-1.5 rounded-lg px-2.5 py-2 text-left ring-1 ring-inset transition ${
                !on ? "cursor-default opacity-40 ring-line/40" : sel ? "bg-elevated ring-2 ring-[#57D7BA]" : "ring-line hover:bg-card"
              }`}
            >
              <div className="flex items-center gap-1.5">
                <span className="h-2 w-2 shrink-0 rounded-full" style={{ background: L.accent }} />
                <span className="truncate text-[12.5px] font-semibold text-cream">{zh ? L.zh : L.en}</span>
                <span className="ml-auto font-mono tabular text-[12px] text-neutral-400">{items.length}</span>
              </div>
              <StanceMini items={items} />
            </button>
          );
        })}
      </div>

      {selLens && selItems.length > 0 && (
        <div className="mt-3">
          <div className="mb-2 flex items-baseline gap-2">
            <span className="h-4 w-1 rounded-full" style={{ background: selLens.accent }} />
            <h4 className="font-display text-[14px] font-bold text-cream">{zh ? selLens.zh : selLens.en}</h4>
            <span className="truncate text-[11.5px] text-neutral-500">{zh ? selLens.qzh : selLens.qen}</span>
            <span className="ml-auto shrink-0 font-mono tabular text-[12px] text-neutral-500">{selItems.length}</span>
          </div>
          <ul className="grid gap-2.5 sm:grid-cols-2">
            {shown.map((o) => (
              <OpinionCard key={`${effSel}:${o.id}`} o={o} zh={zh} tag={(o.viewpoints?.[0] || "other") === effSel ? (zh ? "主" : "main") : undefined} />
            ))}
          </ul>
          {selItems.length > CAP && (
            <button onClick={() => setExpand((v) => !v)} className="mt-2.5 text-[12px] font-medium text-neutral-500 hover:text-cream">
              {expand ? (zh ? "收起" : "Show less") : zh ? `展开全部 ${selItems.length} 条` : `Show all ${selItems.length}`}
            </button>
          )}
        </div>
      )}
    </div>
  );
}
