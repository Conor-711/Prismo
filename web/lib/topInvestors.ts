// 标的「前 N 投资者」数据层（构建期静态读取）。
// 数据由离线管线生成：覆盖该标的的博主，按【跨标的验证过的选股技能 z】排名
//（z 已通过样本外持续性检验，详见 KOL_SKILL_REPORT.md），附该标的战绩 + 最近观点(论据)。
// 当前仅 Palantir(PLTR) 为真实数据，其余标的暂无（模块按需隐藏）。
import data from "./data/topInvestors.json";

export type InvestorStance = "bull" | "bear" | "neutral";

export type InvestorOpinion = {
  date: string;
  stance: InvestorStance;
  text: string;
  url: string;
};

export type TopInvestor = {
  handle: string;
  name: string;
  avatar: string;
  skillZ: number; // 跨标的选股技能 z（越高=越不像运气）
  pltrCalls: number; // 该标的已结算 call 数
  pltrHit: number; // 该标的命中率 0..1（对照 base 看）
  stance: InvestorStance; // 当前立场（近 30 天净）
  latest: InvestorOpinion[]; // 最近观点（论据）
};

export type TopInvestorBoard = {
  base: number; // 该标的盲多 5 日跑赢 SPY 的概率（命中率的参照线）
  investors: TopInvestor[];
};

const MAP = data as unknown as Record<string, TopInvestorBoard>;

export function getTopInvestors(ticker: string): TopInvestorBoard | null {
  return MAP[ticker.toUpperCase()] ?? null;
}
