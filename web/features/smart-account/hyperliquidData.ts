import rawHyperliquidSmartMoney from "@/lib/data/hyperliquidSmartMoney.json";

export type HyperliquidCategory = "stocks" | "indices" | "commodities" | "fx" | "preipo";
export type HyperliquidWindow = "1" | "3" | "7";
export type HyperliquidSignal = "bullish" | "bearish" | "mixed" | "insufficient";

export interface HyperliquidWalletPosition {
  address: string;
  score: number;
  confidence: number;
  position: number;
  notional: number;
  direction: "long" | "short";
  coin: string;
  dex: string;
  lastAction: string;
  lastPrice: number;
  netPnl30d: number;
}

export interface HyperliquidFillEvidence {
  address: string;
  coin: string;
  side: "buy" | "sell";
  action: string;
  price: number;
  size: number;
  notional: number;
  time: string;
  hash: string;
}

export interface HyperliquidMarketSignal {
  qualifiedWallets: number;
  longWallets: number;
  shortWallets: number;
  grossPositionNotional: number;
  netPositionNotional: number;
  consensus: number;
  netFlowNotional: number;
  weightedFlow: number;
  signal: HyperliquidSignal;
  topWallets: HyperliquidWalletPosition[];
  evidence: HyperliquidFillEvidence[];
  dailyFlow: { day: string; value: number }[];
}

export interface HyperliquidMarket {
  symbol: string;
  category: HyperliquidCategory;
  coins: string[];
  venues: string[];
  markPrice: number;
  dayVolume: number;
  openInterestNotional: number;
  signals: Partial<Record<HyperliquidWindow, HyperliquidMarketSignal>>;
}

export interface HyperliquidLeaderboardWallet {
  rank: number;
  address: string;
  score: number;
  rawScore: number;
  confidence: number;
  classification: string;
  fillCount: number;
  closedFillCount: number;
  activeDays: number;
  netPnl: number;
  tradedNotional: number;
  winRate: number;
  profitFactor: number;
  maxDrawdownPnl: number;
  makerRatio: number;
  topMarkets: { symbol: string; notional: number }[];
  components: Record<string, number>;
}

export interface HyperliquidSmartMoneyData {
  version: string;
  scoringVersion: string;
  generatedAt: string;
  lookbackDays: number;
  summary: {
    instrumentCount: number;
    observedWalletCount: number;
    qualifiedWalletCount: number;
    smartWalletCount: number;
    algorithmicExcluded?: number;
    smartScoreThreshold: number;
    dayNotionalVolume?: number;
  };
  categories: HyperliquidCategory[];
  markets: HyperliquidMarket[];
  leaderboard: HyperliquidLeaderboardWallet[];
}

export function getHyperliquidSmartMoneyData(): HyperliquidSmartMoneyData {
  return rawHyperliquidSmartMoney as unknown as HyperliquidSmartMoneyData;
}
