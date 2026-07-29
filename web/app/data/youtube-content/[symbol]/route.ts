import { TICKER_UNIVERSE } from "@/shared/market/tickerMeta";
import { getGrTickerSymbols } from "@/server/queries/globalQueries";
import { getYoutubeOpinionContent } from "@/server/queries/kolQueries";

export const dynamic = "force-static";
export const dynamicParams = false;

export function generateStaticParams() {
  const symbols = getGrTickerSymbols();
  return (symbols.length ? symbols : TICKER_UNIVERSE).map((symbol) => ({ symbol }));
}

export function GET(_request: Request, { params }: { params: { symbol: string } }) {
  const symbol = params.symbol.toUpperCase();
  const content = getYoutubeOpinionContent(symbol);
  return Response.json(
    { symbol, content },
    { headers: { "Cache-Control": "public, max-age=300" } }
  );
}
