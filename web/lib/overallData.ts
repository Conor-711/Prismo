// 标的「整体数据」派生信号的构建期数据层（离线管线 pipeline/analyze/overall_signals.py 产出）。
//   ① anomalies —— 情绪/讨论度异常日 + AI 一句话归因（标在当天的折线/条状物上，hover 出原因）。
//   ② aspects   —— 近 14 天 KOL 最密集讨论的 3 个方面（标签 + 多空倾向 + 代表性原推）。
// 与 topInvestors 同范式：web 端按 ticker 直接读 JSON，不碰 dev.db。当前仅 PLTR 为真实数据。
import data from "./data/overallData.json";

export type AnomalyMetric = "sentiment" | "volume";
export type AnomalyDir = "up" | "down";

export interface OverallAnomaly {
  day: string;
  metric: AnomalyMetric;
  direction: AnomalyDir;
  z: number;
  reason: { zh: string; en: string };
}

// 聪明钱 ↔ 散户 分歧（feature 1）：smart=技能加权 KOL net、retail=散户 net，各按自身峰值归一到 [-1,1]。
export type SentStance = "bull" | "bear" | "neutral";
export interface DivPoint { day: string; smart: number; retail: number }
export interface Divergence {
  series: DivPoint[];
  read: { smart: SentStance; retail: SentStance; diverging: boolean };
  smartAuthors: number; // 进入 smart 线的已验证作者推文数（透明度）
}

export interface OverallData {
  anomalies: OverallAnomaly[];
  divergence?: Divergence | null;
  window?: { start: string; end: string };
  updated_at?: string;
}

const MAP = data as unknown as Record<string, OverallData>;

export function getOverallData(ticker: string): OverallData | null {
  const d = MAP[ticker.toUpperCase()];
  if (!d) return null;
  return {
    anomalies: d.anomalies ?? [],
    divergence: d.divergence ?? null,
    window: d.window,
    updated_at: d.updated_at,
  };
}
