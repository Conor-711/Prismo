import { all } from "@/lib/db";
import type { SmartVoiceEvidenceCall } from "./smartVoiceInvestorQueries";

export interface SmartVoicePortfolioBacktest {
  version: string;
  methodology: {
    mode: string;
    entry: string;
    exit: string;
    allocation: string;
    cashWhenInactive: boolean;
    roundTripCostBps: number;
    riskFreeRate: number;
    sameTickerRule: string;
    overlappingCallsReplaced: number;
  };
  base: SmartVoicePortfolioSimulation;
  costSensitivity: {
    costBps: number;
    totalReturn: number;
    annualizedReturn: number | null;
    sharpe: number | null;
  }[];
}

export interface SmartVoicePortfolioSimulation {
  costBps: number;
  startDay: string;
  endDay: string;
  tradingDays: number;
  activeDays: number;
  tradeCount: number;
  exposurePct: number;
  averageActivePositions: number;
  turnoverUnits: number;
  totalReturn: number;
  annualizedReturn: number | null;
  annualizedExcessReturn: number | null;
  annualizedVolatility: number | null;
  sharpe: number | null;
  sortino: number | null;
  maxDrawdown: number;
  drawdownPeakDay: string;
  drawdownTroughDay: string;
  calmar: number | null;
  positiveActiveDayRate: number | null;
  benchmarkTotalReturn: number;
  benchmarkAnnualizedReturn: number | null;
  benchmarkMaxDrawdown: number;
  beta: number | null;
  annualizedAlpha: number | null;
  yearReturns: {
    year: string;
    return: number;
    benchmarkReturn: number;
  }[];
  equityCurve: {
    day: string;
    strategy: number;
    benchmark: number;
    drawdown: number;
    activePositions: number;
  }[];
}

interface PriceBar {
  day: string;
  open: number;
  close: number;
}

interface PriceSeries {
  bars: PriceBar[];
  days: string[];
  indexByDay: Map<string, number>;
}

interface Position {
  candidateId: string;
  ticker: string;
  direction: 1 | -1;
  entryDay: string;
  exitDay: string;
}

interface RawPriceBar extends PriceBar {
  ticker: string;
}

function mean(values: number[]) {
  return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : 0;
}

function sampleVariance(values: number[]) {
  if (values.length < 2) return 0;
  const average = mean(values);
  return values.reduce((sum, value) => sum + (value - average) ** 2, 0) / (values.length - 1);
}

function sampleCovariance(left: number[], right: number[]) {
  if (left.length < 2 || left.length !== right.length) return 0;
  const leftMean = mean(left);
  const rightMean = mean(right);
  return left.reduce(
    (sum, value, index) => sum + (value - leftMean) * (right[index] - rightMean),
    0,
  ) / (left.length - 1);
}

function annualizedReturn(totalReturn: number, tradingDays: number) {
  if (tradingDays <= 0 || totalReturn <= -1) return null;
  return (1 + totalReturn) ** (252 / tradingDays) - 1;
}

function lowerBound(values: string[], target: string) {
  let low = 0;
  let high = values.length;
  while (low < high) {
    const middle = Math.floor((low + high) / 2);
    if (values[middle] < target) low = middle + 1;
    else high = middle;
  }
  return low;
}

function priceBook(tickers: string[], startDay: string, endDay: string) {
  const requested = [...new Set([...tickers.map((ticker) => ticker.toUpperCase()), "SPY"])];
  const rows: RawPriceBar[] = [];
  for (let offset = 0; offset < requested.length; offset += 200) {
    const batch = requested.slice(offset, offset + 200);
    const placeholders = batch.map(() => "?").join(", ");
    rows.push(...all<RawPriceBar>(
      `SELECT upper(ticker) AS ticker,
              day,
              CASE
                WHEN close > 0 AND adj_close > 0 THEN open * adj_close / close
                ELSE open
              END AS open,
              COALESCE(NULLIF(adj_close, 0), close) AS close
         FROM price_daily
        WHERE ticker IN (${placeholders})
          AND day BETWEEN ? AND ?
          AND open > 0
          AND COALESCE(NULLIF(adj_close, 0), close) > 0
        ORDER BY ticker, day`,
      ...batch,
      startDay,
      endDay,
    ));
  }

  const grouped = new Map<string, PriceBar[]>();
  for (const row of rows) {
    const ticker = String(row.ticker);
    const bars = grouped.get(ticker) ?? [];
    bars.push({
      day: String(row.day),
      open: Number(row.open),
      close: Number(row.close),
    });
    grouped.set(ticker, bars);
  }
  return new Map(
    [...grouped.entries()].map(([ticker, bars]) => [
      ticker,
      {
        bars,
        days: bars.map((bar) => bar.day),
        indexByDay: new Map(bars.map((bar, index) => [bar.day, index])),
      } satisfies PriceSeries,
    ]),
  );
}

function canonicalPositions(
  calls: SmartVoiceEvidenceCall[],
  prices: Map<string, PriceSeries>,
): { positions: Position[]; replaced: number } {
  const grouped = new Map<string, SmartVoiceEvidenceCall[]>();
  for (const call of calls) {
    if (!["bull", "bear"].includes(call.direction) || !call.entryDay || !call.exitDay) continue;
    const ticker = call.ticker.toUpperCase();
    const tickerCalls = grouped.get(ticker) ?? [];
    tickerCalls.push(call);
    grouped.set(ticker, tickerCalls);
  }

  const positions: Position[] = [];
  let replaced = 0;
  for (const [ticker, tickerCalls] of grouped) {
    const series = prices.get(ticker);
    if (!series) continue;
    const latestByEntry = new Map<string, SmartVoiceEvidenceCall>();
    for (const call of [...tickerCalls].sort((left, right) =>
      left.entryDay.localeCompare(right.entryDay)
      || left.day.localeCompare(right.day)
      || left.candidateId.localeCompare(right.candidateId)
    )) {
      if (latestByEntry.has(call.entryDay)) replaced += 1;
      latestByEntry.set(call.entryDay, call);
    }
    const ordered = [...latestByEntry.values()].sort((left, right) =>
      left.entryDay.localeCompare(right.entryDay)
    );
    ordered.forEach((call, index) => {
      let exitDay = call.exitDay;
      if (!series.indexByDay.has(call.entryDay) || !series.indexByDay.has(exitDay)) return;
      const nextEntry = ordered[index + 1]?.entryDay;
      if (nextEntry && nextEntry <= exitDay) {
        const nextIndex = lowerBound(series.days, nextEntry);
        if (nextIndex <= 0) {
          replaced += 1;
          return;
        }
        exitDay = series.days[nextIndex - 1];
        replaced += 1;
      }
      if (exitDay < call.entryDay) return;
      positions.push({
        candidateId: call.candidateId,
        ticker,
        direction: call.direction === "bull" ? 1 : -1,
        entryDay: call.entryDay,
        exitDay,
      });
    });
  }
  positions.sort((left, right) =>
    left.entryDay.localeCompare(right.entryDay)
    || left.ticker.localeCompare(right.ticker)
    || left.candidateId.localeCompare(right.candidateId)
  );
  return { positions, replaced };
}

function maxDrawdown(equity: number[], days: string[]) {
  let peak = equity[0];
  let peakDay = days[0];
  let worst = 0;
  let worstPeakDay = peakDay;
  let troughDay = peakDay;
  const drawdowns: number[] = [];
  equity.forEach((value, index) => {
    if (value > peak) {
      peak = value;
      peakDay = days[index];
    }
    const drawdown = peak ? value / peak - 1 : 0;
    drawdowns.push(drawdown);
    if (drawdown < worst) {
      worst = drawdown;
      worstPeakDay = peakDay;
      troughDay = days[index];
    }
  });
  return { value: worst, peakDay: worstPeakDay, troughDay, drawdowns };
}

function yearReturns(days: string[], strategyReturns: number[], benchmarkReturns: number[]) {
  const grouped = new Map<string, { strategy: number[]; benchmark: number[] }>();
  days.forEach((day, index) => {
    const year = day.slice(0, 4);
    const values = grouped.get(year) ?? { strategy: [], benchmark: [] };
    values.strategy.push(strategyReturns[index]);
    values.benchmark.push(benchmarkReturns[index]);
    grouped.set(year, values);
  });
  return [...grouped.entries()].map(([year, values]) => ({
    year,
    return: values.strategy.reduce((equity, value) => equity * (1 + value), 1) - 1,
    benchmarkReturn: values.benchmark.reduce((equity, value) => equity * (1 + value), 1) - 1,
  }));
}

function simulate(
  positions: Position[],
  prices: Map<string, PriceSeries>,
  benchmark: PriceSeries,
  costBps: number,
): SmartVoicePortfolioSimulation | null {
  const dailyComponents = new Map<string, { value: number; entry: boolean; exit: boolean }[]>();
  for (const position of positions) {
    const series = prices.get(position.ticker);
    const entryIndex = series?.indexByDay.get(position.entryDay);
    const exitIndex = series?.indexByDay.get(position.exitDay);
    if (!series || entryIndex == null || exitIndex == null || exitIndex < entryIndex) continue;
    for (let index = entryIndex; index <= exitIndex; index += 1) {
      const bar = series.bars[index];
      const base = index === entryIndex ? bar.open : series.bars[index - 1].close;
      if (base <= 0) continue;
      const components = dailyComponents.get(bar.day) ?? [];
      components.push({
        value: position.direction * (bar.close / base - 1),
        entry: index === entryIndex,
        exit: index === exitIndex,
      });
      dailyComponents.set(bar.day, components);
    }
  }
  if (!positions.length) return null;
  const firstDay = positions[0].entryDay;
  const lastDay = positions.reduce((latest, position) => position.exitDay > latest ? position.exitDay : latest, "");
  const benchmarkBars = benchmark.bars.filter((bar) => firstDay <= bar.day && bar.day <= lastDay);
  if (!benchmarkBars.length) return null;

  const days: string[] = [];
  const strategyReturns: number[] = [];
  const benchmarkReturns: number[] = [];
  const activeCounts: number[] = [];
  const turnover: number[] = [];
  const halfCost = Math.max(0, costBps) / 20_000;
  let previousBenchmarkClose = 0;

  benchmarkBars.forEach((bar) => {
    const components = dailyComponents.get(bar.day) ?? [];
    const count = components.length;
    const gross = count ? mean(components.map((component) => component.value)) : 0;
    const dayTurnover = count
      ? components.reduce((sum, component) => sum + Number(component.entry) + Number(component.exit), 0) / count
      : 0;
    const benchmarkBase = previousBenchmarkClose || bar.open;
    days.push(bar.day);
    strategyReturns.push(Math.max(-0.99, gross - halfCost * dayTurnover));
    benchmarkReturns.push(benchmarkBase > 0 ? bar.close / benchmarkBase - 1 : 0);
    activeCounts.push(count);
    turnover.push(dayTurnover);
    previousBenchmarkClose = bar.close;
  });

  const strategyEquity: number[] = [];
  const benchmarkEquity: number[] = [];
  let strategyValue = 1;
  let benchmarkValue = 1;
  strategyReturns.forEach((value, index) => {
    strategyValue *= 1 + value;
    benchmarkValue *= 1 + benchmarkReturns[index];
    strategyEquity.push(strategyValue);
    benchmarkEquity.push(benchmarkValue);
  });

  const totalReturn = strategyValue - 1;
  const benchmarkTotalReturn = benchmarkValue - 1;
  const cagr = annualizedReturn(totalReturn, days.length);
  const benchmarkCagr = annualizedReturn(benchmarkTotalReturn, days.length);
  const variance = sampleVariance(strategyReturns);
  const volatility = variance > 0 ? Math.sqrt(variance) : null;
  const downside = Math.sqrt(mean(strategyReturns.map((value) => Math.min(0, value) ** 2)));
  const drawdown = maxDrawdown(strategyEquity, days);
  const benchmarkDrawdown = maxDrawdown(benchmarkEquity, days);
  const benchmarkVariance = sampleVariance(benchmarkReturns);
  const beta = benchmarkVariance > 0
    ? sampleCovariance(strategyReturns, benchmarkReturns) / benchmarkVariance
    : null;
  const activeReturns = strategyReturns.filter((_, index) => activeCounts[index] > 0);

  return {
    costBps,
    startDay: days[0],
    endDay: days.at(-1) ?? days[0],
    tradingDays: days.length,
    activeDays: activeCounts.filter((count) => count > 0).length,
    tradeCount: positions.length,
    exposurePct: activeCounts.filter((count) => count > 0).length / days.length,
    averageActivePositions: mean(activeCounts),
    turnoverUnits: turnover.reduce((sum, value) => sum + value, 0),
    totalReturn,
    annualizedReturn: cagr,
    annualizedExcessReturn: cagr != null && benchmarkCagr != null ? cagr - benchmarkCagr : null,
    annualizedVolatility: volatility == null ? null : volatility * Math.sqrt(252),
    sharpe: volatility ? mean(strategyReturns) / volatility * Math.sqrt(252) : null,
    sortino: downside > 0 ? mean(strategyReturns) / downside * Math.sqrt(252) : null,
    maxDrawdown: drawdown.value,
    drawdownPeakDay: drawdown.peakDay,
    drawdownTroughDay: drawdown.troughDay,
    calmar: cagr != null && drawdown.value < 0 ? cagr / Math.abs(drawdown.value) : null,
    positiveActiveDayRate: activeReturns.length
      ? activeReturns.filter((value) => value > 0).length / activeReturns.length
      : null,
    benchmarkTotalReturn,
    benchmarkAnnualizedReturn: benchmarkCagr,
    benchmarkMaxDrawdown: benchmarkDrawdown.value,
    beta,
    annualizedAlpha: beta == null
      ? null
      : (mean(strategyReturns) - beta * mean(benchmarkReturns)) * 252,
    yearReturns: yearReturns(days, strategyReturns, benchmarkReturns),
    equityCurve: days.map((day, index) => ({
      day,
      strategy: strategyEquity[index],
      benchmark: benchmarkEquity[index],
      drawdown: drawdown.drawdowns[index],
      activePositions: activeCounts[index],
    })),
  };
}

export function getSmartVoicePortfolioBacktest(
  calls: SmartVoiceEvidenceCall[],
): SmartVoicePortfolioBacktest | null {
  const executable = calls.filter((call) =>
    ["bull", "bear"].includes(call.direction) && call.entryDay && call.exitDay
  );
  if (!executable.length) return null;
  const startDay = executable.reduce(
    (earliest, call) => !earliest || call.entryDay < earliest ? call.entryDay : earliest,
    "",
  );
  const endDay = executable.reduce(
    (latest, call) => call.exitDay > latest ? call.exitDay : latest,
    "",
  );
  const prices = priceBook(executable.map((call) => call.ticker), startDay, endDay);
  const benchmark = prices.get("SPY");
  if (!benchmark) return null;
  const { positions, replaced } = canonicalPositions(executable, prices);
  if (!positions.length) return null;
  const simulations = [0, 10, 25]
    .map((costBps) => simulate(positions, prices, benchmark, costBps))
    .filter((simulation): simulation is SmartVoicePortfolioSimulation => simulation != null);
  const base = simulations.find((simulation) => simulation.costBps === 10);
  if (!base) return null;
  return {
    version: "smart-voice-equal-weight-v1",
    methodology: {
      mode: "long_short",
      entry: "next_trading_day_adjusted_open",
      exit: "primary_horizon_or_next_same_ticker_call",
      allocation: "equal_weight_active_tickers",
      cashWhenInactive: true,
      roundTripCostBps: 10,
      riskFreeRate: 0,
      sameTickerRule: "latest_call_replaces_previous",
      overlappingCallsReplaced: replaced,
    },
    base,
    costSensitivity: simulations.map((simulation) => ({
      costBps: simulation.costBps,
      totalReturn: simulation.totalReturn,
      annualizedReturn: simulation.annualizedReturn,
      sharpe: simulation.sharpe,
    })),
  };
}
