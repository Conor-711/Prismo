import { TICKER_UNIVERSE } from "@/shared/market/tickerMeta";
import { getGrTickerSymbols } from "@/server/queries/globalQueries";
import {
  getKolArguments,
  getKolSentimentDaily,
  getKolTargetPrices,
  getKolVolumeDaily,
  getRetailSentimentDaily,
  getRetailVolumeDaily,
} from "@/server/queries/kolQueries";
import { getOverallData } from "@/server/queries/overallData";

export const dynamic = "force-static";
export const dynamicParams = false;

export function generateStaticParams() {
  const symbols = getGrTickerSymbols();
  return (symbols.length ? symbols : TICKER_UNIVERSE).map((symbol) => ({ symbol }));
}

export function GET(_request: Request, { params }: { params: { symbol: string } }) {
  const symbol = params.symbol.toUpperCase();
  return Response.json(
    {
      symbol,
      sentiment: getKolSentimentDaily(symbol),
      volume: getKolVolumeDaily(symbol),
      retailSentiment: getRetailSentimentDaily(symbol),
      retailVolume: getRetailVolumeDaily(symbol),
      overall: getOverallData(symbol),
      targetPrices: getKolTargetPrices(symbol),
      argumentsData: getKolArguments(symbol),
    },
    { headers: { "Cache-Control": "public, max-age=300" } }
  );
}
