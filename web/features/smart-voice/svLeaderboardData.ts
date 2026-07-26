import type {
  SvBoard,
  SvConfidence,
  SvHorizon,
  SvInvestor,
  SvSource,
} from "./svMock";

export const SMART_VOICE_LEADERBOARD_SOURCES = ["x", "youtube", "reddit", "xueqiu"] as const;
export type SmartVoiceLeaderboardSource = (typeof SMART_VOICE_LEADERBOARD_SOURCES)[number];

export interface SmartVoiceLeaderboardInvestor {
  id: string;
  rank?: number;
  platformRank?: number;
  observationRank?: number;
  source: SvSource;
  name: string;
  handle: string;
  avatar?: string;
  url?: string;
  sv: number;
  confidence: SvConfidence;
  nEff: number;
  settledCalls: number;
  activeDays: number;
  coveredTickers: number;
  topTickers: string[];
  platformScores: Partial<Record<SvSource, number>>;
  horizonScores: Partial<Record<SvHorizon, number | null>>;
  dominantInvestorType?: string;
  rationaleZh: string;
  rationaleEn: string;
}

export interface SmartVoiceLeaderboardBand {
  rankedIds: string[];
  observedIds: string[];
  top10Ids: string[];
  bottom10Ids: string[];
}

export interface SmartVoiceLeaderboardData {
  investors: Record<string, SmartVoiceLeaderboardInvestor>;
  bands: Partial<Record<SmartVoiceLeaderboardSource, SmartVoiceLeaderboardBand>>;
}

function compactInvestor(investor: SvInvestor): SmartVoiceLeaderboardInvestor {
  return {
    id: investor.id,
    rank: investor.rank,
    platformRank: investor.platformRank,
    observationRank: investor.observationRank,
    source: investor.source,
    name: investor.name,
    handle: investor.handle,
    avatar: investor.avatar,
    url: investor.url,
    sv: investor.sv,
    confidence: investor.confidence,
    nEff: investor.nEff,
    settledCalls: investor.settledCalls,
    activeDays: investor.activeDays,
    coveredTickers: investor.coveredTickers,
    topTickers: investor.topTickers,
    platformScores: investor.platformScores,
    horizonScores: investor.horizonScores,
    dominantInvestorType: investor.concentration?.dominantInvestorType,
    rationaleZh: investor.rationaleZh,
    rationaleEn: investor.rationaleEn,
  };
}

export function buildSmartVoiceLeaderboardData(board: SvBoard): SmartVoiceLeaderboardData {
  const investors: Record<string, SmartVoiceLeaderboardInvestor> = {};
  const add = (items: SvInvestor[]) => {
    for (const investor of items) {
      const compact = compactInvestor(investor);
      investors[investor.id] = investors[investor.id]
        ? { ...investors[investor.id], ...compact }
        : compact;
    }
    return items.map((investor) => investor.id);
  };

  const bands: SmartVoiceLeaderboardData["bands"] = {};
  for (const source of SMART_VOICE_LEADERBOARD_SOURCES) {
    const band = board.platformBands?.[source];
    const fallback = board[source]?.length
      ? board[source]
      : [...board.investors, ...(board.bottomInvestors ?? [])].filter((investor) => investor.source === source);
    const ranked = band?.ranked ?? fallback;
    const observed = band?.observed ?? [];
    const top10 = band?.top10 ?? ranked.slice(0, Math.max(1, Math.ceil(ranked.length * 0.1)));
    const bottom10 = band?.bottom10 ?? [...ranked].sort((a, b) => a.sv - b.sv).slice(0, Math.max(1, Math.ceil(ranked.length * 0.1)));
    bands[source] = {
      rankedIds: add(ranked),
      observedIds: add(observed),
      top10Ids: add(top10),
      bottom10Ids: add(bottom10),
    };
  }

  return { investors, bands };
}
