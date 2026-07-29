import { TICKER_UNIVERSE } from "@/shared/market/tickerMeta";
import { getGrTickerSymbols } from "@/server/queries/globalQueries";
import { getKolOpinionContent } from "@/server/queries/kolQueries";

export const dynamic = "force-static";
export const dynamicParams = false;

export function generateStaticParams() {
  const symbols = getGrTickerSymbols();
  return (symbols.length ? symbols : TICKER_UNIVERSE).map((symbol) => ({ symbol }));
}

export function GET(_request: Request, { params }: { params: { symbol: string } }) {
  const symbol = params.symbol.toUpperCase();
  return Response.json(
    { symbol, content: getKolOpinionContent(symbol) },
    { headers: { "Cache-Control": "public, max-age=300" } }
  );
}
