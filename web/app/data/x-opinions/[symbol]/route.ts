import { TICKER_UNIVERSE } from "@/shared/market/tickerMeta";
import { getGrTickerSymbols } from "@/server/queries/globalQueries";
import { getCompleteXOpinions } from "@/server/queries/kolQueries";

export const dynamic = "force-static";
export const dynamicParams = false;

export function generateStaticParams() {
  const symbols = getGrTickerSymbols();
  return (symbols.length ? symbols : TICKER_UNIVERSE).map((symbol) => ({ symbol }));
}

export function GET(_request: Request, { params }: { params: { symbol: string } }) {
  const symbol = params.symbol.toUpperCase();
  const opinions = getCompleteXOpinions(symbol);
  return Response.json(
    {
      symbol,
      count: opinions.length,
      minDay: opinions.reduce((min, opinion) => (!min || opinion.day < min ? opinion.day : min), ""),
      maxDay: opinions.reduce((max, opinion) => (opinion.day > max ? opinion.day : max), ""),
      opinions,
    },
    { headers: { "Cache-Control": "public, max-age=300" } }
  );
}
