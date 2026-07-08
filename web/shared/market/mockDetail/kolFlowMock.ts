import { TOPICS, pick, r2, rng, type Bi } from "./marketMock";
import type { KolCandle, KolFlow, KolOpinion, KolSource, Stance } from "./kolTypes";

const KOL_AUTHORS: Record<KolSource, string[]> = {
  x: ["@DeepValueDan", "@ChartFanatic", "@MacroMaverick", "@OptionsOwl", "@TheRoaringKid"],
  youtube: ["Meet Kevin", "Tom Nash", "Joseph Carlson", "Ticker Symbol YOU", "Graham Stephan"],
  reddit: ["u/DeepFvalue", "u/wsb_oracle", "u/value_DD_guy", "u/SemiAnalyst", "u/macro_monk"],
  xueqiu: ["不明真相的群众", "梁宏", "云蒙", "Ricky", "处镜如初"],
  toss: ["토스개미", "장기투자자", "반도체노트", "주식초보", "가치투자"],
  yahoojp: ["掲示板投資家", "NISA長期派", "半導体ウォッチャー", "個人投資家A", "決算メモ"],
};

function kolText(topic: Bi, stance: Stance): Bi {
  if (stance === "bull") return { zh: `${topic.zh}——继续看多，逢低加仓`, en: `${topic.en} — staying long, adding on dips` };
  if (stance === "bear") return { zh: `${topic.zh}——短线见顶，先减仓观望`, en: `${topic.en} — topping near-term, trimming here` };
  return { zh: `${topic.zh}——先观望，等方向确认`, en: `${topic.en} — sidelined, waiting for confirmation` };
}

export function getKolFlow(symbol: string): KolFlow {
  const rnd = rng("KOL:" + symbol);
  const SOURCES: KolSource[] = ["x", "youtube", "reddit", "xueqiu", "toss", "yahoojp"];
  const WINDOW_DAYS = 16; // 自然日窗口，跳周末后约 11 个交易日（近 2 周）
  const today = new Date("2026-06-22T00:00:00Z"); // 固定参照 → 快照不漂移
  const days: KolCandle[] = [];
  const opinions: KolOpinion[] = [];

  let prevClose = 60 + Math.floor(rnd() * 900); // 标的基价
  const drift = (rnd() - 0.45) * 0.6; // 轻微趋势

  for (let i = WINDOW_DAYS - 1; i >= 0; i--) {
    const d = new Date(today);
    d.setUTCDate(today.getUTCDate() - i);
    const dow = d.getUTCDay();
    if (dow === 0 || dow === 6) continue; // 跳过周末
    const day = d.toISOString().slice(0, 10);

    const vol = prevClose * (0.012 + rnd() * 0.03);
    const open = r2(prevClose + (rnd() - 0.5) * vol * 0.4);
    const close = r2(Math.max(1, open + (rnd() - 0.5) * vol * 2 + drift * prevClose * 0.01));
    const high = r2(Math.max(open, close) + rnd() * vol);
    const low = r2(Math.max(0.5, Math.min(open, close) - rnd() * vol));
    days.push({ day, open, high, low, close });
    prevClose = close;

    // 当天观点数 0..6（偶尔爆量）；立场略与当日涨跌相关
    const up = close >= open;
    const n = Math.floor(rnd() * 4) + (rnd() > 0.7 ? Math.floor(rnd() * 4) : 0);
    for (let k = 0; k < n; k++) {
      const source = pick(SOURCES, rnd);
      const sb = rnd();
      const stance: Stance = sb < (up ? 0.55 : 0.3) ? "bull" : sb < (up ? 0.8 : 0.7) ? "neutral" : "bear";
      const topic = pick(TOPICS, rnd);
      const viral = rnd() > 0.86;
      const interactions = Math.floor(viral ? 8000 + rnd() * 58000 : 80 + rnd() * 4200);
      // mock 视角：1-2 个（首个为主视角），让 mock 兜底时「按视角」视图也有内容
      const VK = ["valuation", "growth", "competition", "management", "macro", "catalyst", "flows"];
      const v1 = pick(VK, rnd);
      const viewpoints = rnd() > 0.78 ? ["other"] : rnd() > 0.55 ? [v1, pick(VK.filter((x) => x !== v1), rnd)] : [v1];
      const author = pick(KOL_AUTHORS[source], rnd);
      opinions.push({
        id: `${symbol}-${day}-${k}`,
        day,
        source,
        author,
        authorRefId: `${source}:${author.replace(/^@/, "").replace(/^u\//, "").trim()}`,
        interactions,
        stance,
        text: kolText(topic, stance),
        url: "#",
        viewpoints,
      });
    }
  }
  return { days, opinions };
}
