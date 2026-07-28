export type DashboardSignalKey = "divergence" | "bullish" | "bearish";

export interface DashboardSignalItem {
  ticker: string;
  nameZh: string;
  nameEn: string;
  posts: number;
  sentiment: number;
  spread: number;
  divergentRegion: string;
}

export interface DashboardBuzzItem {
  ticker: string;
  nameZh: string;
  nameEn: string;
  posts: number;
  regions: number;
  sentiment: number;
  bull: number;
  bear: number;
  neutral: number;
}

export interface DashboardVoiceItem {
  id: string;
  name: string;
  handle: string;
  source: "x" | "youtube" | "reddit" | "xueqiu" | "toss";
  language: string;
  score: number;
  confidence: string;
  settledCalls: number;
  topTickers: string[];
}

export interface DashboardQuoteMove {
  ticker: string;
  changePct: number;
}

export interface DashboardModel {
  empty: boolean;
  meta: {
    tickers: number;
    posts: number;
    regions: number;
    lastUpdated: string | null;
  };
  market: {
    topGainer: DashboardQuoteMove | null;
    topLoser: DashboardQuoteMove | null;
    topDivergence: DashboardSignalItem | null;
  };
  signals: Record<DashboardSignalKey, DashboardSignalItem[]>;
  heatmap: {
    regionCodes: string[];
    tickers: string[];
    cells: [number, number, number][];
  };
  buzz: DashboardBuzzItem[];
  voices: DashboardVoiceItem[];
  narratives: { key: string; zh: string; en: string; weight: number }[];
  voicePool: number;
}
