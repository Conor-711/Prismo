"use client";

// 全局搜索热度（Supabase 后端）。未配置 Supabase 时全部优雅降级：
// recordSearch 静默跳过，fetchTopSearches 返回 []（页面改用真实「社区热度」兜底）。
// 后端 schema 见 supabase/migrations/20260610000001_ticker_searches.sql。
import { supabase } from "./supabase";

export interface SearchCount {
  ticker: string;
  count: number;
}

// 记录一次真实搜索（fire-and-forget；失败不影响跳转体验）。
export async function recordSearch(ticker: string): Promise<void> {
  const t = ticker.trim().toUpperCase();
  if (!supabase || !t) return;
  try {
    await supabase.rpc("increment_ticker_search", { p_ticker: t });
  } catch {
    /* 网络/未配置 → 忽略 */
  }
}

// 读取全网搜索榜前 N。未配置或出错 → []。
export async function fetchTopSearches(limit = 10): Promise<SearchCount[]> {
  if (!supabase) return [];
  try {
    const { data, error } = await supabase
      .from("ticker_searches")
      .select("ticker, search_count")
      .order("search_count", { ascending: false })
      .limit(limit);
    if (error || !data) return [];
    return data
      .filter((r) => (r.search_count ?? 0) > 0)
      .map((r) => ({ ticker: r.ticker as string, count: Number(r.search_count) || 0 }));
  } catch {
    return [];
  }
}
