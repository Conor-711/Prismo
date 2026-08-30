import { getTickerSmartVoiceSignals } from "@/server/queries/smartVoiceTickerSignals";

export const dynamic = "force-static";
export const dynamicParams = false;

export function generateStaticParams() {
  return ["MU", "NVDA", "MSTR"].map((symbol) => ({ symbol }));
}

export function GET(_request: Request, { params }: { params: { symbol: string } }) {
  const symbol = params.symbol.toUpperCase();
  return Response.json(
    { symbol, data: getTickerSmartVoiceSignals(symbol) },
    { headers: { "Cache-Control": "public, max-age=300" } }
  );
}
