import { REGION_ORDER } from "@/shared/market/regions";
import type { GrMeta, GrQuoteRow, GrRegionCell, GrTickerRow } from "@/server/queries/globalQueries";
import type { SvBoard } from "@/features/smart-account";
import type {
  DashboardBuzzItem,
  DashboardModel,
  DashboardSignalItem,
} from "./types";

function signalItem(ticker: GrTickerRow): DashboardSignalItem {
  return {
    ticker: ticker.ticker,
    nameZh: ticker.name_zh,
    nameEn: ticker.name_en,
    posts: ticker.total_posts,
    sentiment: ticker.avg_sentiment,
    spread: ticker.spread ?? 0,
    divergentRegion: ticker.divergent_region ?? "",
  };
}

export function buildDashboardModel({
  meta,
  tickers,
  cells,
  quotes,
  svBoard,
}: {
  meta: GrMeta;
  tickers: GrTickerRow[];
  cells: GrRegionCell[];
  quotes: GrQuoteRow[];
  svBoard: SvBoard;
}): DashboardModel {
  const byPosts = [...tickers].sort((a, b) => b.total_posts - a.total_posts);
  const divergence = [...tickers]
    .filter((ticker) => (ticker.spread ?? 0) > 0)
    .sort((a, b) => (b.spread ?? 0) - (a.spread ?? 0))
    .slice(0, 8)
    .map(signalItem);
  const bullish = [...tickers]
    .sort((a, b) => b.avg_sentiment - a.avg_sentiment)
    .slice(0, 8)
    .map(signalItem);
  const bearish = [...tickers]
    .sort((a, b) => a.avg_sentiment - b.avg_sentiment)
    .slice(0, 8)
    .map(signalItem);

  const stanceByTicker = new Map<string, { bull: number; bear: number; neutral: number }>();
  for (const cell of cells) {
    const current = stanceByTicker.get(cell.ticker) ?? { bull: 0, bear: 0, neutral: 0 };
    current.bull += (cell.bull_pct || 0) * (cell.post_count || 0);
    current.bear += (cell.bear_pct || 0) * (cell.post_count || 0);
    current.neutral += (cell.neutral_pct || 0) * (cell.post_count || 0);
    stanceByTicker.set(cell.ticker, current);
  }

  const buzz: DashboardBuzzItem[] = byPosts.slice(0, 10).map((ticker) => {
    const stance = stanceByTicker.get(ticker.ticker) ?? { bull: 0, bear: 0, neutral: 0 };
    return {
      ticker: ticker.ticker,
      nameZh: ticker.name_zh,
      nameEn: ticker.name_en,
      posts: ticker.total_posts,
      regions: ticker.regions_present,
      sentiment: ticker.avg_sentiment,
      ...stance,
    };
  });

  const presentRegions = new Set(cells.map((cell) => cell.region));
  const regionCodes = REGION_ORDER.filter((region) => presentRegions.has(region));

  const heatTickers = byPosts.slice(0, 12).map((ticker) => ticker.ticker);
  const cellMap = new Map(cells.map((cell) => [`${cell.region}:${cell.ticker}`, cell.sentiment_avg]));
  const heatCells: [number, number, number][] = [];
  heatTickers.forEach((ticker, tickerIndex) => {
    regionCodes.forEach((region, regionIndex) => {
      const value = cellMap.get(`${region}:${ticker}`);
      if (value != null) heatCells.push([regionIndex, tickerIndex, Math.round(value * 100) / 100]);
    });
  });

  const gainers = quotes
    .filter((quote) => quote.change_pct > 0)
    .sort((a, b) => b.change_pct - a.change_pct);
  const losers = quotes
    .filter((quote) => quote.change_pct < 0)
    .sort((a, b) => a.change_pct - b.change_pct);

  return {
    empty: tickers.length === 0,
    meta,
    market: {
      topGainer: gainers[0] ? { ticker: gainers[0].ticker, changePct: gainers[0].change_pct } : null,
      topLoser: losers[0] ? { ticker: losers[0].ticker, changePct: losers[0].change_pct } : null,
      topDivergence: divergence[0] ?? null,
    },
    signals: { divergence, bullish, bearish },
    heatmap: { regionCodes, tickers: heatTickers, cells: heatCells },
    buzz,
    voices: [...svBoard.investors]
      .sort((a, b) => b.sv - a.sv)
      .slice(0, 8)
      .map((investor) => ({
        id: investor.id,
        name: investor.name,
        handle: investor.handle,
        source: investor.source,
        language: investor.language,
        score: investor.sv,
        confidence: investor.confidence,
        settledCalls: investor.settledCalls,
        topTickers: investor.topTickers.slice(0, 3),
      })),
    narratives: svBoard.currentNarratives,
    voicePool: svBoard.totalInvestors ?? svBoard.investors.length,
  };
}
