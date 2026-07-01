"use client";

// KOL 模块共享：来源/立场配色、日期格式化、观点卡 + 头像。供折线K线图与 KOL/视角/热度 三种分类视图复用。
import { useState } from "react";
import { fmtCompact } from "@/lib/format";
import type { KolOpinion, KolSource, Stance, Bi } from "@/lib/mockDetail";

export const SOURCE: Record<KolSource, { color: string; label: string }> = {
  x: { color: "#8C96A2", label: "X" },
  youtube: { color: "#E0A33E", label: "YouTube" },
  reddit: { color: "#E07A55", label: "Reddit" },
  xueqiu: { color: "#5BA3C4", label: "雪球" },
};
export const SOURCE_ORDER: KolSource[] = ["x", "youtube", "reddit", "xueqiu"];

// 每日讨论度堆叠条形图的「平台层」配置（自底向上）。VolumePanel 据此渲染，两种人群口径各一套。
export interface VolStackItem { key: string; zh: string; en: string; color: string }
// KOL 视图：X / YouTube / Reddit / 雪球（沿用 SOURCE 配色）。
export const KOL_VOL_STACK: VolStackItem[] = [
  { key: "reddit", zh: "Reddit", en: "Reddit", color: SOURCE.reddit.color },
  { key: "x", zh: "X", en: "X", color: SOURCE.x.color },
  { key: "xueqiu", zh: "雪球", en: "Xueqiu", color: SOURCE.xueqiu.color },
  { key: "youtube", zh: "YouTube", en: "YouTube", color: SOURCE.youtube.color },
];
// 整体散户视图：X / Reddit / 雪球 + 本土散户论坛 Naver(韩) / Yahoo JP / PTT(台) / Toss(韩，预留)。不含 YouTube。
export const RETAIL_VOL_STACK: VolStackItem[] = [
  { key: "reddit", zh: "Reddit", en: "Reddit", color: SOURCE.reddit.color },
  { key: "x", zh: "X", en: "X", color: SOURCE.x.color },
  { key: "xueqiu", zh: "雪球", en: "Xueqiu", color: SOURCE.xueqiu.color },
  { key: "naver", zh: "Naver", en: "Naver", color: "#5FA86E" },
  { key: "yahoojp", zh: "Yahoo JP", en: "Yahoo JP", color: "#C77B9A" },
  { key: "ptt", zh: "PTT", en: "PTT", color: "#9B8ECF" },
  { key: "toss", zh: "Toss", en: "Toss", color: "#D6A24A" },
];
// 「每日新增散户」堆叠层：整体散户口径，但**不含 X**（云端无作者列、无法定位新增者）、不含 YouTube（创作者非散户）。
export const RETAIL_NEW_STACK: VolStackItem[] = [
  { key: "reddit", zh: "Reddit", en: "Reddit", color: SOURCE.reddit.color },
  { key: "xueqiu", zh: "雪球", en: "Xueqiu", color: SOURCE.xueqiu.color },
  { key: "naver", zh: "Naver", en: "Naver", color: "#5FA86E" },
  { key: "yahoojp", zh: "Yahoo JP", en: "Yahoo JP", color: "#C77B9A" },
  { key: "ptt", zh: "PTT", en: "PTT", color: "#9B8ECF" },
  { key: "toss", zh: "Toss", en: "Toss", color: "#D6A24A" },
];
// 「每日新增 KOL」堆叠层：仅 X / YouTube / 雪球（有显著身份、粉丝数象征的平台；不含 Reddit 等匿名源）。
export const KOL_NEW_STACK: VolStackItem[] = [
  { key: "x", zh: "X", en: "X", color: SOURCE.x.color },
  { key: "youtube", zh: "YouTube", en: "YouTube", color: SOURCE.youtube.color },
  { key: "xueqiu", zh: "雪球", en: "Xueqiu", color: SOURCE.xueqiu.color },
];
export const STANCE: Record<Stance, { color: string; zh: string; en: string }> = {
  bull: { color: "#57D7BA", zh: "看多", en: "Bull" },
  bear: { color: "#FF5C6C", zh: "看空", en: "Bear" },
  neutral: { color: "#7A8A96", zh: "中性", en: "Neutral" },
};

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
export const mmdd = (d: string) => {
  const [, m, dd] = d.split("-");
  return `${+m}/${+dd}`;
};
export const longDay = (d: string, zh: boolean) => {
  const [, m, dd] = d.split("-");
  return zh ? `${+m} 月 ${+dd} 日` : `${MONTHS[+m - 1]} ${+dd}`;
};

// 优先展示 AI 提炼的「为什么」（reason）；无提炼则回退原文/标题（text）
export const opinionText = (o: KolOpinion, zh: boolean) => {
  const r = o.reason ? (zh ? o.reason.zh : o.reason.en) : "";
  return r || (zh ? o.text.zh : o.text.en);
};
export const opinionPoints = (o: KolOpinion, zh: boolean) =>
  (o.points ? (zh ? o.points.zh : o.points.en) : []).filter(Boolean).slice(0, 3);

// 「原文 + 译」取文（原帖卡通用，原帖流与「按 KOL」共用）。
// 当原文非当前界面语言（CJK 粗判）且有该语言的忠实译文时，默认展示译文，给「看原文」选项。
export const CJK_RE = /[一-鿿぀-ヿ가-힯]/;
export function pickOriginal(
  o: { orig?: string; text?: Bi; trans?: Bi; quote?: Bi },
  zh: boolean
): { base: string; trans: string; canTranslate: boolean } {
  const pick = (b?: Bi) => (b ? (zh ? b.zh : b.en) : "");
  const base = o.orig || pick(o.text) || pick(o.trans) || pick(o.quote);
  const tr = pick(o.trans) || pick(o.quote) || pick(o.text);
  const cjk = CJK_RE.test(base);
  const canTranslate =
    (zh ? !cjk : cjk) && !!tr && tr.trim() !== base.trim() && (zh ? CJK_RE.test(tr) : !CJK_RE.test(tr));
  return { base, trans: tr, canTranslate };
}

export function Avatar({ src, color, name, size = 32 }: { src?: string; color: string; name: string; size?: number }) {
  const [bad, setBad] = useState(false);
  const initial = (name || "?").replace(/^u\//, "").trim().charAt(0).toUpperCase() || "?";
  if (src && !bad) {
    // eslint-disable-next-line @next/next/no-img-element
    return (
      <img
        src={src}
        alt=""
        loading="lazy"
        onError={() => setBad(true)}
        style={{ width: size, height: size }}
        className="shrink-0 rounded-full bg-elevated object-cover ring-1 ring-inset ring-line"
      />
    );
  }
  return (
    <span
      aria-hidden
      className="grid shrink-0 place-items-center rounded-full font-bold text-[#121212]"
      style={{ background: color, width: size, height: size, fontSize: Math.round(size * 0.42) }}
    >
      {initial}
    </span>
  );
}

// 单条原帖卡：头像 + 来源/作者 + 立场 + 互动 + 帖子正文 + 翻译/原文切换 + 回原帖。tag 可选（视角「主」标）。
// 与「按视角·原帖流」一致：展示帖子正文而非 AI 提炼；原文异语种时默认用界面语言展示。
// compact=true：去掉头像与来源/作者行（用于「按 KOL」分组——作者身份已在分组头展示）。
export function OpinionCard({ o, zh, tag, compact }: { o: KolOpinion; zh: boolean; tag?: string; compact?: boolean }) {
  const [showT, setShowT] = useState(false);
  const s = STANCE[o.stance];
  const src = SOURCE[o.source];
  const { base, trans, canTranslate } = pickOriginal(o, zh);
  const showOriginal = showT && canTranslate;
  const displayText = showOriginal ? base : (canTranslate ? trans : base);
  const hasLink = !!o.url && o.url !== "#";
  const body = (
    <div className="min-w-0 flex-1">
      <div className="flex items-center gap-2 text-[12px]">
        {!compact && <span className="font-semibold" style={{ color: src.color }}>{src.label}</span>}
        {!compact && <span className="min-w-0 truncate text-neutral-400">{o.author}</span>}
        {tag && <span className="shrink-0 rounded bg-elevated px-1 py-px text-[10px] text-neutral-500">{tag}</span>}
        <span className={`flex shrink-0 items-center gap-2 ${compact ? "" : "ml-auto"}`}>
          <span className="font-medium" style={{ color: s.color }}>{zh ? s.zh : s.en}</span>
          <span className="font-mono tabular text-neutral-500">{fmtCompact(o.interactions)}</span>
        </span>
      </div>
      {displayText && (
        <p className="mt-1 whitespace-pre-line text-[13.5px] leading-relaxed text-cream">
          {displayText}
        </p>
      )}
      {(canTranslate || hasLink) && (
        <div className="mt-1.5 flex items-center gap-3 text-[11px]">
          {canTranslate && (
            <button onClick={() => setShowT((v) => !v)} className="text-neutral-500 transition hover:text-[#57D7BA]">
              {showOriginal ? (zh ? "看译文" : "Translation") : (zh ? "看原文" : "Original")}
            </button>
          )}
          {hasLink && (
            <a href={o.url} target="_blank" rel="noreferrer" className="text-neutral-500 transition hover:text-[#57D7BA]">
              {zh ? "查看原帖 ↗" : "View original ↗"}
            </a>
          )}
        </div>
      )}
    </div>
  );
  return (
    <li className="flex gap-3 rounded-lg bg-card px-3.5 py-3 ring-1 ring-inset ring-line">
      {!compact && <Avatar src={o.avatar} color={src.color} name={o.author} />}
      {body}
    </li>
  );
}
