import { all, parseJSON } from "@/lib/db";
import type { Bi, KolSource, Stance } from "@/shared/market/mockDetail";
import { safe, type RawOp } from "./shared";
import { avatarMap, refinedMap } from "./lookups";
import { redditOps, tossOps, xMergedOps, yahooJpOps, youtubeOps, xueqiuOps } from "./sources";

// ===================== 论点综合（kol_argument，标的页『按视角』视图）=====================
// pipeline kol-argument 把同一(标的×视角×立场)下的观点聚成 1-3 个论点，supporters 回指 source+item_id。
// 这一层**与时间轴滑块解耦**：展示「当前整体争论」，故独立取数、不按价格窗口过滤。
export type LensKey =
  | "valuation" | "growth" | "competition" | "management" | "macro" | "catalyst" | "flows";

export interface ArgSupporter {
  source: KolSource;
  author: string;
  avatar?: string;
  url: string;
  interactions: number;
  stance: Stance;
  day?: string; // 发布日（时效排序 + 展示）
  orig?: string; // 原帖原文（native 语言、未翻译；卡片默认展示）
  text?: Bi; // 当前语言显示文本（reddit/youtube 双语；x/雪球为原文）
  trans?: Bi; // 原帖完整忠实翻译（逐句、不压缩；「译」选项首选）
  quote?: Bi; // 本人忠实原话（一句 soundbite，译文回退用）
  reason?: Bi; // AI 提炼（旧观点视图回退用）
}
export interface KolArgument {
  lens: LensKey;
  stance: Stance;
  claim: Bi; // 一句话主张
  detail?: Bi; // 一句支撑推理
  supportCount: number;
  supporters: ArgSupporter[];
}
export interface Narrative { lead?: Bi; points: { text: Bi; supporters: ArgSupporter[] }[] }
export interface StanceGroup { narrative?: Narrative; args: KolArgument[] }
export interface LensArgGroup { bull: StanceGroup; neutral: StanceGroup; bear: StanceGroup }
export type KolArguments = Partial<Record<LensKey, LensArgGroup>>;
export type WindowedArguments = Record<string, KolArguments>; // 时间窗 key（24h|3d|7d|14d|1mo）-> 该窗论点

// 浮现分（方案A 排序核心）：互动量（对数）为主，叠加「具体性」（含数字/$/%/催化词→更可读、更可证伪）
// 与「时效」（近期略加权），把值得先读的原帖顶到前面。纯启发式、零 LLM。
const SPEC_RE = /[0-9$%＄％]|\b(beat|miss|guidance|guide|earnings|catalyst|fda|deal|buyback|margin|revenue|eps)\b|财报|催化|业绩|回购|毛利|营收|交付|订单/i;
function supporterScore(s: ArgSupporter): number {
  const eng = Math.log10((s.interactions || 0) + 1); // 0 ~ 5+
  const txt = `${s.text?.zh || ""} ${s.text?.en || ""} ${s.quote?.zh || ""}`;
  const spec = SPEC_RE.test(txt) ? 0.6 : 0;
  const rec = s.day ? Math.max(0, 1 - (Date.now() - Date.parse(s.day + "T00:00:00Z")) / (30 * 864e5)) * 0.5 : 0;
  return eng + spec + rec;
}

export function getKolArguments(symbol: string): WindowedArguments {
  return safe(() => {
    const rows = all<any>(
      `SELECT window, lens, stance, claim_zh, claim_en, detail_zh, detail_en, supporters, support_count
         FROM kol_argument WHERE ticker = ? ORDER BY window, lens, stance, rank`,
      symbol
    );
    if (!rows.length) return {};

    // 该标的观点索引（source:item_id -> 展示信息），用于把 supporters 解析成头像/原话/原帖。
    // 用较宽窗口（~30 天，覆盖 refine 的 20 天）以确保 supporters 可解析，与滑块无关。
    const cutoff = new Date(Date.now() - 30 * 864e5).toISOString().slice(0, 10);
    const rawIdx = new Map<string, RawOp>();
    for (const op of [
      ...redditOps(symbol, cutoff, 200),
      ...youtubeOps(symbol, cutoff, 80),
      ...xueqiuOps(symbol, cutoff, 200),
      ...tossOps(symbol, cutoff, 200),
      ...yahooJpOps(symbol, cutoff, 200),
      ...xMergedOps(symbol, cutoff, 200),
    ]) rawIdx.set(`${op.source}:${op.refKey}`, op);
    const refined = refinedMap(symbol);
    const avatars = avatarMap();

    const resolve = (s: { source: string; item_id: string }): ArgSupporter | null => {
      const key = `${s.source}:${s.item_id}`;
      const raw = rawIdx.get(key);
      const ref = refined.get(key);
      if (!raw && !ref) return null;
      const source = (raw?.source || s.source) as KolSource;
      const avatar =
        (raw ? avatars.get(`${source}:${raw.avatarKey}`) : undefined) ||
        (source === "x" && raw?.avatarKey ? `https://unavatar.io/twitter/${raw.avatarKey}` : undefined);
      const quote = ref?.quote && (ref.quote.zh || ref.quote.en) ? ref.quote : undefined;
      const trans = ref?.trans && (ref.trans.zh || ref.trans.en) ? ref.trans : undefined;
      const reason = ref?.reason && (ref.reason.zh || ref.reason.en) ? ref.reason : raw?.reason;
      return {
        source,
        author: raw?.author || (source === "xueqiu" ? "雪球" : source === "toss" ? "Toss" : source === "yahoojp" ? "Yahoo JP" : source),
        avatar,
        url: raw?.url || "#",
        interactions: raw?.interactions || 0,
        stance: ref?.stance || raw?.stance || "neutral",
        day: raw?.day,
        orig: raw?.orig,
        text: raw && (raw.zh || raw.en) ? { zh: raw.zh || raw.en, en: raw.en || raw.zh } : quote,
        trans,
        quote,
        reason,
      };
    };

    const out: WindowedArguments = {};
    for (const r of rows) {
      const w = String(r.window || "14d");
      const lens = r.lens as LensKey;
      const stance = ((r.stance as Stance) || "neutral") as Stance;
      const claim: Bi = { zh: r.claim_zh || r.claim_en || "", en: r.claim_en || r.claim_zh || "" };
      if (!claim.zh && !claim.en) continue;
      const supporters = parseJSON<{ source: string; item_id: string }[]>(r.supporters, [])
        .map(resolve)
        .filter((x): x is ArgSupporter => !!x)
        .sort((a, b) => supporterScore(b) - supporterScore(a));
      const arg: KolArgument = {
        lens,
        stance,
        claim,
        detail: r.detail_zh || r.detail_en ? { zh: r.detail_zh || r.detail_en, en: r.detail_en || r.detail_zh } : undefined,
        supportCount: r.support_count || supporters.length,
        supporters,
      };
      const ow = (out[w] ||= {});
      const g = (ow[lens] ||= { bull: { args: [] }, neutral: { args: [] }, bear: { args: [] } });
      (stance === "bull" ? g.bull : stance === "bear" ? g.bear : g.neutral).args.push(arg);
    }
    // 叙事（kol_narrative）：每条 point 的 refs → 支持者头像/原帖角标，按 (窗口,视角,立场) 挂上
    for (const n of safe(
      () => all<any>("SELECT window, lens, stance, lead_zh, lead_en, points FROM kol_narrative WHERE ticker = ?", symbol),
      [] as any[]
    )) {
      const ow = out[String(n.window || "14d")];
      if (!ow) continue;
      const g = ow[n.lens as LensKey];
      if (!g) continue;
      const lead = n.lead_zh || n.lead_en ? { zh: n.lead_zh || n.lead_en, en: n.lead_en || n.lead_zh } : undefined;
      const points = parseJSON<any[]>(n.points, []).map((p) => ({
        text: { zh: p.zh || p.en || "", en: p.en || p.zh || "" } as Bi,
        supporters: ((p.refs || []) as { source: string; item_id: string }[])
          .map(resolve)
          .filter((x): x is ArgSupporter => !!x)
          .sort((a, b) => supporterScore(b) - supporterScore(a)),
      }));
      const stance = (n.stance as Stance) || "neutral";
      (stance === "bull" ? g.bull : stance === "bear" ? g.bear : g.neutral).narrative = { lead, points };
    }
    return out;
  }, {});
}
