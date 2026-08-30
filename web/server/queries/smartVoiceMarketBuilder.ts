import {
  createSmartVoiceTickerAggregate,
  emptySmartVoiceEvidenceIds,
  selectSmartVoiceEvidence,
  smartVoiceCallWeight,
  smartVoiceEvidenceBucket,
  smartVoiceSignal,
  type SmartVoiceEvidenceBucket,
  type SmartVoiceTickerAggregate,
} from "./smartVoiceMarketAggregation";
import type { SmartVoiceMarketSource, SmartVoiceRawCall, SmartVoiceTickerBoards, SmartVoiceTickerEvidence, SmartVoiceTickerRank } from "./smartVoiceTypes";

export function buildSmartVoiceTickerBoards(
  rows: SmartVoiceRawCall[],
  limit: number,
  rankScope: "global" | "platform" = "global",
  evidenceById?: Record<string, SmartVoiceTickerEvidence>,
  previousRows: SmartVoiceRawCall[] = [],
  historyRows: SmartVoiceRawCall[] = [],
): SmartVoiceTickerBoards {
  const byTicker = new Map<string, SmartVoiceTickerAggregate>();

  for (const row of previousRows) {
    const current = byTicker.get(row.ticker) ?? createSmartVoiceTickerAggregate(row);
    const rankBand = rankScope === "platform" ? row.platformRankBand : row.rankBand;
    if (rankBand !== "top") {
      byTicker.set(row.ticker, current);
      continue;
    }
    const authorKey = row.investorId || row.handle || row.evidenceId;
    const platformAuthorKey = `${row.source}:${authorKey}`;
    const previous = current.previousTopAuthorStates.get(platformAuthorKey);
    if (!previous || row.createdAt > previous.createdAt || (row.createdAt === previous.createdAt && row.evidenceId > previous.evidenceId)) {
      current.previousTopAuthorStates.set(platformAuthorKey, {
        direction: row.direction,
        createdAt: row.createdAt,
        evidenceId: row.evidenceId,
      });
    }
    const bucket: SmartVoiceEvidenceBucket = row.direction === "bull" ? "previousHighBull" : "previousHighBear";
    const weight = smartVoiceCallWeight(row, rankScope);
    current.evidenceBuckets[bucket].push({
      authorKey: platformAuthorKey,
      priority: weight * (0.75 + Math.max(0, Math.min(1, row.evidenceScore || 0)) * 0.25),
      evidence: createEvidence(row, "top"),
    });
    byTicker.set(row.ticker, current);
  }

  for (const row of rows) {
    const current = byTicker.get(row.ticker) ?? createSmartVoiceTickerAggregate(row);
    const weight = smartVoiceCallWeight(row, rankScope);
    const signedWeight = row.direction === "bull" ? weight : -weight;
    const rankBand = rankScope === "platform" ? row.platformRankBand : row.rankBand;
    if (row.direction === "bull") {
      current.bullScore += weight;
      current.nBull += 1;
      if (rankBand === "top") current.highBullScore += weight;
      if (rankBand === "bottom") current.lowBullScore += weight;
      if (row.handle) current.bullHandles.add(row.handle);
    } else {
      current.bearScore += weight;
      current.nBear += 1;
      if (rankBand === "top") current.highBearScore += weight;
      if (rankBand === "bottom") current.lowBearScore += weight;
      if (row.handle) current.bearHandles.add(row.handle);
    }
    const bucket = smartVoiceEvidenceBucket(rankBand, row.direction);
    if (bucket) {
      const authorKey = row.investorId || row.handle || row.evidenceId;
      const platformAuthorKey = `${row.source}:${authorKey}`;
      current.handleBuckets[bucket].add(platformAuthorKey);
      if (bucket === "highBull") current.highBullCalls += 1;
      if (bucket === "highBear") current.highBearCalls += 1;
      if (bucket === "lowBull") current.lowBullCalls += 1;
      if (bucket === "lowBear") current.lowBearCalls += 1;
      current.evidenceBuckets[bucket].push({
        authorKey: platformAuthorKey,
        priority: weight * (0.75 + Math.max(0, Math.min(1, row.evidenceScore || 0)) * 0.25),
        evidence: createEvidence(row, rankBand as "top" | "bottom"),
      });
      if (rankBand === "top") {
        const previous = current.topAuthorStates.get(platformAuthorKey);
        if (!previous || row.createdAt > previous.createdAt || (row.createdAt === previous.createdAt && row.evidenceId > previous.evidenceId)) {
          current.topAuthorStates.set(platformAuthorKey, {
            direction: row.direction,
            createdAt: row.createdAt,
            evidenceId: row.evidenceId,
          });
        }
      }
    }
    current.nPosts += 1;
    current.netScore += signedWeight;
    current.highNet = current.highBullScore - current.highBearScore;
    current.lowNet = current.lowBullScore - current.lowBearScore;
    current.contrastScore = Math.abs(current.highNet - current.lowNet);
    current.bullVoices = current.bullHandles.size;
    current.bearVoices = current.bearHandles.size;
    current.nVoices = new Set([...current.bullHandles, ...current.bearHandles]).size;
    current.highBullVoices = current.handleBuckets.highBull.size;
    current.highBearVoices = current.handleBuckets.highBear.size;
    current.lowBullVoices = current.handleBuckets.lowBull.size;
    current.lowBearVoices = current.handleBuckets.lowBear.size;
    current.highVoices = new Set([...current.handleBuckets.highBull, ...current.handleBuckets.highBear]).size;
    current.lowVoices = new Set([...current.handleBuckets.lowBull, ...current.handleBuckets.lowBear]).size;
    current.handleScore.set(row.handle, (current.handleScore.get(row.handle) ?? 0) + Math.abs(weight));
    byTicker.set(row.ticker, current);
  }

  const ranked = [...byTicker.values()]
    .filter((row) => row.highBullCalls + row.highBearCalls + row.lowBullCalls + row.lowBearCalls >= 3 || row.previousTopAuthorStates.size >= 2)
    .map((row) => {
      const latestAuthorDirections = [...row.topAuthorStates.values()];
      const previousAuthorDirections = [...row.previousTopAuthorStates.values()];
      row.highAuthorBullCount = latestAuthorDirections.filter((state) => state.direction === "bull").length;
      row.highAuthorBearCount = latestAuthorDirections.filter((state) => state.direction === "bear").length;
      row.highAuthorNet = row.highAuthorBullCount - row.highAuthorBearCount;
      row.highAuthorConsensus = latestAuthorDirections.length ? (row.highAuthorNet / latestAuthorDirections.length) * 100 : 0;
      row.previousHighAuthorBullCount = previousAuthorDirections.filter((state) => state.direction === "bull").length;
      row.previousHighAuthorBearCount = previousAuthorDirections.filter((state) => state.direction === "bear").length;
      row.previousHighAuthorNet = row.previousHighAuthorBullCount - row.previousHighAuthorBearCount;
      row.previousHighAuthorConsensus = previousAuthorDirections.length ? (row.previousHighAuthorNet / previousAuthorDirections.length) * 100 : 0;
      row.authorNetDelta = row.highAuthorNet - row.previousHighAuthorNet;
      const currentAuthorTotal = latestAuthorDirections.length;
      const previousAuthorTotal = previousAuthorDirections.length;
      const authorBase = Math.max(1, currentAuthorTotal, previousAuthorTotal);
      row.authorNetShiftPct = (row.authorNetDelta / authorBase) * 100;
      row.authorNetAbrupt = Math.abs(row.authorNetDelta) >= 3
        && Math.abs(row.authorNetShiftPct) >= 50
        && currentAuthorTotal >= 3
        && previousAuthorTotal >= 3;
      row.signal = smartVoiceSignal(row);
      row.topHandles = [...row.handleScore.entries()]
        .sort((a, b) => b[1] - a[1])
        .slice(0, 3)
        .map(([handle]) => handle);
      const { handleScore, bullHandles, bearHandles, handleBuckets, topAuthorStates, previousTopAuthorStates, ...rest } = row;
      return {
        ...rest,
        bullScore: +rest.bullScore.toFixed(2),
        bearScore: +rest.bearScore.toFixed(2),
        netScore: +rest.netScore.toFixed(2),
        highBullScore: +rest.highBullScore.toFixed(2),
        highBearScore: +rest.highBearScore.toFixed(2),
        lowBullScore: +rest.lowBullScore.toFixed(2),
        lowBearScore: +rest.lowBearScore.toFixed(2),
        highNet: +rest.highNet.toFixed(2),
        lowNet: +rest.lowNet.toFixed(2),
        contrastScore: +rest.contrastScore.toFixed(2),
        highAuthorConsensus: +rest.highAuthorConsensus.toFixed(1),
        previousHighAuthorConsensus: +rest.previousHighAuthorConsensus.toFixed(1),
        authorNetShiftPct: +rest.authorNetShiftPct.toFixed(1),
      };
    });

  const finalize = (items: typeof ranked, includePreviousEvidence = false): SmartVoiceTickerRank[] => items.map((row) => {
    const { evidenceBuckets, ...rest } = row;
    return {
      ...rest,
      evidenceIds: {
        highBull: selectSmartVoiceEvidence(evidenceBuckets.highBull, evidenceById),
        highBear: selectSmartVoiceEvidence(evidenceBuckets.highBear, evidenceById),
        lowBull: selectSmartVoiceEvidence(evidenceBuckets.lowBull, evidenceById),
        lowBear: selectSmartVoiceEvidence(evidenceBuckets.lowBear, evidenceById),
        previousHighBull: includePreviousEvidence ? selectSmartVoiceEvidence(evidenceBuckets.previousHighBull, evidenceById) : [],
        previousHighBear: includePreviousEvidence ? selectSmartVoiceEvidence(evidenceBuckets.previousHighBear, evidenceById) : [],
      },
    };
  });

  const authorShiftRanked = [...ranked]
    .filter((row) => row.authorNetDelta !== 0 && Math.max(
      row.highAuthorBullCount + row.highAuthorBearCount,
      row.previousHighAuthorBullCount + row.previousHighAuthorBearCount,
    ) >= 2)
    .sort((a, b) => Number(b.authorNetAbrupt) - Number(a.authorNetAbrupt)
      || Math.abs(b.authorNetShiftPct) - Math.abs(a.authorNetShiftPct)
      || Math.abs(b.authorNetDelta) - Math.abs(a.authorNetDelta)
      || a.ticker.localeCompare(b.ticker))
    .slice(0, limit);
  authorShiftRanked.forEach((row, index) => {
    row.authorNetShiftRank = index + 1;
  });

  return {
    bullish: finalize([...ranked]
      .filter((row) => row.highNet > 0 && row.highBullCalls >= 2 && row.highBullVoices >= 2)
      .sort((a, b) => b.highNet - a.highNet || b.highBullScore - a.highBullScore)
      .slice(0, limit)),
    bearish: finalize([...ranked]
      .filter((row) => row.highNet < 0 && row.highBearCalls >= 2 && row.highBearVoices >= 2)
      .sort((a, b) => a.highNet - b.highNet || b.highBearScore - a.highBearScore)
      .slice(0, limit)),
    contrast: finalize([...ranked]
      .filter((row) => row.highNet * row.lowNet < 0 && row.contrastScore > 1.5 && row.highVoices >= 2 && row.lowVoices >= 2)
      .sort((a, b) => b.contrastScore - a.contrastScore)
      .slice(0, limit)),
    authorShift: finalize(authorShiftRanked, true),
    newCoverage: buildNewCoverage(rows, historyRows, limit, rankScope, evidenceById),
  };
}

function createEvidence(
  row: SmartVoiceRawCall,
  rankBand: "top" | "bottom",
): SmartVoiceTickerEvidence {
  return {
    id: row.evidenceId,
    ticker: row.ticker,
    source: row.source as SmartVoiceMarketSource,
    direction: row.direction,
    rankBand,
    author: row.handle || row.investorId || "Unknown",
    createdAt: row.createdAt,
    platformSv: +row.platformSv.toFixed(1),
    confidence: row.confidence,
    callWeight: +row.callWeight.toFixed(2),
    horizon: row.horizon,
    targetPrice: row.targetPrice,
    summaryZh: "",
    summaryEn: "",
    originalEvidence: "",
    url: "",
  };
}

function buildNewCoverage(
  rows: SmartVoiceRawCall[],
  historyRows: SmartVoiceRawCall[],
  limit: number,
  rankScope: "global" | "platform",
  evidenceById?: Record<string, SmartVoiceTickerEvidence>,
): SmartVoiceTickerRank[] {
  const rankBandOf = (row: SmartVoiceRawCall) => rankScope === "platform" ? row.platformRankBand : row.rankBand;
  const authorOf = (row: SmartVoiceRawCall) => `${row.source}:${row.investorId || row.handle || row.evidenceId}`;
  const authorTickerKey = (row: SmartVoiceRawCall) => `${authorOf(row)}:${row.ticker}`;
  const priorAuthorTickers = new Set<string>();
  const priorAuthorsByTicker = new Map<string, Set<string>>();

  for (const row of historyRows) {
    if (rankBandOf(row) !== "top") continue;
    const authorKey = authorOf(row);
    priorAuthorTickers.add(authorTickerKey(row));
    const tickerAuthors = priorAuthorsByTicker.get(row.ticker) ?? new Set<string>();
    tickerAuthors.add(authorKey);
    priorAuthorsByTicker.set(row.ticker, tickerAuthors);
  }

  // Each top-ranked author contributes only the latest call for a ticker in the current window.
  const latestByAuthorTicker = new Map<string, SmartVoiceRawCall>();
  const currentAuthorsByTicker = new Map<string, Set<string>>();
  for (const row of rows) {
    if (rankBandOf(row) !== "top") continue;
    const key = authorTickerKey(row);
    const previous = latestByAuthorTicker.get(key);
    if (!previous || row.createdAt > previous.createdAt || (row.createdAt === previous.createdAt && row.evidenceId > previous.evidenceId)) {
      latestByAuthorTicker.set(key, row);
    }
    const tickerAuthors = currentAuthorsByTicker.get(row.ticker) ?? new Set<string>();
    tickerAuthors.add(authorOf(row));
    currentAuthorsByTicker.set(row.ticker, tickerAuthors);
  }

  const byTicker = new Map<string, SmartVoiceTickerAggregate>();
  for (const [authorTicker, row] of latestByAuthorTicker) {
    if (priorAuthorTickers.has(authorTicker)) continue;
    const current = byTicker.get(row.ticker) ?? createSmartVoiceTickerAggregate(row);
    const authorKey = authorOf(row);
    const weight = smartVoiceCallWeight(row, rankScope);
    const bucket: SmartVoiceEvidenceBucket = row.direction === "bull" ? "highBull" : "highBear";
    current.newCoverageAuthorCount += 1;
    current.newCoverageScore += weight;
    current.newestMentionAt = row.createdAt > current.newestMentionAt ? row.createdAt : current.newestMentionAt;
    if (row.direction === "bull") {
      current.newCoverageBullCount += 1;
      current.highBullCalls += 1;
      current.highBullScore += weight;
    } else {
      current.newCoverageBearCount += 1;
      current.highBearCalls += 1;
      current.highBearScore += weight;
    }
    current.evidenceBuckets[bucket].push({
      authorKey,
      priority: weight * (0.75 + Math.max(0, Math.min(1, row.evidenceScore || 0)) * 0.25),
      evidence: createEvidence(row, "top"),
    });
    current.handleScore.set(authorKey, (current.handleScore.get(authorKey) ?? 0) + weight);
    byTicker.set(row.ticker, current);
  }

  return [...byTicker.values()]
    .map((row) => {
      row.currentTopAuthorCount = currentAuthorsByTicker.get(row.ticker)?.size ?? 0;
      row.priorTopAuthorCount = priorAuthorsByTicker.get(row.ticker)?.size ?? 0;
      row.cohortNew = row.priorTopAuthorCount === 0;
      row.newCoverageRatio = row.currentTopAuthorCount
        ? (row.newCoverageAuthorCount / row.currentTopAuthorCount) * 100
        : 0;
      row.highAuthorBullCount = row.newCoverageBullCount;
      row.highAuthorBearCount = row.newCoverageBearCount;
      row.highAuthorNet = row.newCoverageBullCount - row.newCoverageBearCount;
      row.highAuthorConsensus = row.newCoverageAuthorCount
        ? (row.highAuthorNet / row.newCoverageAuthorCount) * 100
        : 0;
      row.highNet = row.highBullScore - row.highBearScore;
      row.signal = smartVoiceSignal(row);
      row.topHandles = [...row.handleScore.entries()]
        .sort((a, b) => b[1] - a[1])
        .slice(0, 3)
        .map(([handle]) => handle.replace(/^[^:]+:/, ""));
      return row;
    })
    .sort((a, b) => Number(b.cohortNew) - Number(a.cohortNew)
      || b.newCoverageAuthorCount - a.newCoverageAuthorCount
      || b.newCoverageScore - a.newCoverageScore
      || b.newCoverageRatio - a.newCoverageRatio
      || b.newestMentionAt.localeCompare(a.newestMentionAt)
      || a.ticker.localeCompare(b.ticker))
    .slice(0, limit)
    .map((row) => {
      const { handleScore, bullHandles, bearHandles, handleBuckets, topAuthorStates, previousTopAuthorStates, evidenceBuckets, ...rest } = row;
      return {
        ...rest,
        highBullScore: +rest.highBullScore.toFixed(2),
        highBearScore: +rest.highBearScore.toFixed(2),
        highNet: +rest.highNet.toFixed(2),
        highAuthorConsensus: +rest.highAuthorConsensus.toFixed(1),
        newCoverageRatio: +rest.newCoverageRatio.toFixed(1),
        newCoverageScore: +rest.newCoverageScore.toFixed(2),
        evidenceIds: {
          ...emptySmartVoiceEvidenceIds(),
          highBull: selectSmartVoiceEvidence(evidenceBuckets.highBull, evidenceById),
          highBear: selectSmartVoiceEvidence(evidenceBuckets.highBear, evidenceById),
        },
      };
    });
}
