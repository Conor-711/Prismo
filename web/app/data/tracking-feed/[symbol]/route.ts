import { TICKER_UNIVERSE } from "@/shared/market/tickerMeta";
import type { KolOpinion } from "@/shared/market/mockDetail";
import { getGrTickerSymbols } from "@/server/queries/globalQueries";
import { getKolOpinions } from "@/server/queries/kolQueries";
import { getTickerSmartVoicePool } from "@/features/smart-account/svMock";
import {
  getOpinionSvMeta,
  highQualityFallbackScore,
  svKeysForInvestor,
} from "@/features/ticker/opinionExplorerLogic";
import type { SvOpinionMeta } from "@/features/ticker/opinionExplorerTypes";
import type { TrackingFeedItem } from "@/features/tracking/trackingTypes";

export const dynamic = "force-static";
export const dynamicParams = false;

export function generateStaticParams() {
  const symbols = getGrTickerSymbols();
  return (symbols.length ? symbols : TICKER_UNIVERSE).map((symbol) => ({ symbol }));
}

export function GET(_request: Request, { params }: { params: { symbol: string } }) {
  const symbol = params.symbol.toUpperCase();
  const opinions = getKolOpinions(symbol, { preview: true, includeContent: false })
    .filter((opinion) => opinion.source !== "yahoojp");
  const board = getTickerSmartVoicePool(symbol);
  const count = board.investors.length;
  const svByKey = new Map<string, SvOpinionMeta>();
  board.investors.forEach((investor, index) => {
    const meta: SvOpinionMeta = {
      rank: index + 1,
      percentile: count ? ((index + 0.5) / count) * 100 : 100,
      score: investor.contextualSv,
      investor,
    };
    for (const key of svKeysForInvestor(investor)) {
      svByKey.set(`${investor.source}:${key}`, meta);
    }
  });

  const compact = compactPool(opinions);
  const items: TrackingFeedItem[] = compact.map((opinion) => {
    const sv = getOpinionSvMeta(opinion, svByKey);
    return {
      symbol,
      opinion,
      narrativeKey: board.narrative.key,
      svScore: sv?.score,
      svRank: sv?.rank,
      svPopulation: count || undefined,
      svPercentile: sv?.percentile,
    };
  });

  return Response.json(
    { symbol, items },
    { headers: { "Cache-Control": "public, max-age=300" } },
  );
}

function compactPool(opinions: KolOpinion[]): KolOpinion[] {
  const latest = [...opinions]
    .sort((a, b) => b.day.localeCompare(a.day) || b.interactions - a.interactions)
    .slice(0, 44);
  const quality = [...opinions]
    .sort((a, b) => highQualityFallbackScore(b) - highQualityFallbackScore(a))
    .slice(0, 52);
  const byId = new Map<string, KolOpinion>();
  for (const opinion of [...latest, ...quality]) byId.set(`${opinion.source}:${opinion.id}`, opinion);
  return [...byId.values()].slice(0, 80);
}
