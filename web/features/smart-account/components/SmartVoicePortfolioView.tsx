"use client";

import { useMemo } from "react";
import ReactECharts from "echarts-for-react";
import type { SmartVoicePortfolioBacktest } from "@/server/queries/smartVoicePortfolioQueries";

const BULL = "#57D7BA";
const CREAM = "#F2F4F5";
const MUTED = "#707780";

function pct(value: number | null, digits = 1) {
  if (value == null) return "—";
  return `${value >= 0 ? "+" : ""}${(value * 100).toFixed(digits)}%`;
}

function number(value: number | null, digits = 2) {
  return value == null ? "—" : value.toFixed(digits);
}

export function SmartVoicePortfolioView({
  backtest,
  zh,
}: {
  backtest: SmartVoicePortfolioBacktest;
  zh: boolean;
}) {
  const base = backtest.base;
  const chartOption = useMemo(() => ({
    animation: false,
    backgroundColor: "transparent",
    grid: { left: 8, right: 54, top: 24, bottom: 36, containLabel: true },
    tooltip: {
      trigger: "axis",
      backgroundColor: "#202328",
      borderColor: "#3A4149",
      textStyle: { color: CREAM, fontSize: 10 },
      formatter: (raw: any) => {
        const params = Array.isArray(raw) ? raw : [raw];
        const day = params[0]?.axisValue ?? "";
        return [
          `<b>${day}</b>`,
          ...params.map((item: any) => `${item.marker}${item.seriesName} ${Number(item.data).toFixed(1)}`),
        ].join("<br/>");
      },
    },
    legend: {
      top: 0,
      right: 0,
      textStyle: { color: MUTED, fontSize: 9 },
      itemWidth: 16,
      itemHeight: 2,
    },
    xAxis: {
      type: "category",
      data: base.equityCurve.map((item) => item.day),
      boundaryGap: false,
      axisTick: { show: false },
      axisLine: { lineStyle: { color: "#343A42" } },
      axisLabel: {
        color: MUTED,
        fontSize: 9,
        hideOverlap: true,
        formatter: (value: string) => value.slice(0, 7),
      },
    },
    yAxis: {
      type: "value",
      scale: true,
      position: "right",
      axisLabel: { color: MUTED, fontSize: 9 },
      splitLine: { lineStyle: { color: "rgba(112,119,128,.12)" } },
    },
    dataZoom: [
      { type: "inside", start: 0, end: 100 },
      {
        type: "slider",
        height: 12,
        bottom: 2,
        borderColor: "#343A42",
        fillerColor: "rgba(87,215,186,.10)",
        handleStyle: { color: BULL },
        textStyle: { color: MUTED, fontSize: 8 },
      },
    ],
    series: [
      {
        name: zh ? "跟随组合" : "Follow portfolio",
        type: "line",
        data: base.equityCurve.map((item) => item.strategy * 100),
        symbol: "none",
        lineStyle: { color: BULL, width: 2 },
      },
      {
        name: "SPY",
        type: "line",
        data: base.equityCurve.map((item) => item.benchmark * 100),
        symbol: "none",
        lineStyle: { color: "#C5CCD3", width: 1.5 },
      },
    ],
  }), [base.equityCurve, zh]);

  const metrics = [
    [zh ? "累计收益" : "Total return", pct(base.totalReturn), base.totalReturn >= 0],
    [zh ? "年化收益" : "CAGR", pct(base.annualizedReturn), (base.annualizedReturn ?? 0) >= 0],
    [zh ? "年化超额" : "Annual excess", pct(base.annualizedExcessReturn), (base.annualizedExcessReturn ?? 0) >= 0],
    [zh ? "同期 SPY 年化" : "SPY CAGR", pct(base.benchmarkAnnualizedReturn), true],
    [zh ? "年化波动" : "Annual vol", pct(base.annualizedVolatility), false],
    ["Sharpe", number(base.sharpe), (base.sharpe ?? 0) >= 1],
    ["Sortino", number(base.sortino), (base.sortino ?? 0) >= 1],
    [zh ? "最大回撤" : "Max drawdown", pct(base.maxDrawdown), false],
  ] as const;

  return (
    <section className="h-full overflow-y-auto">
      <header className="border-b border-line px-4 py-3">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <div>
            <h2 className="text-[13px] font-bold text-cream">
              {zh ? "跟随观点组合回测" : "Follow-the-call portfolio backtest"}
            </h2>
            <p className="mt-1 text-[10px] text-neutral-600">
              {base.startDay} → {base.endDay} · {base.tradeCount} {zh ? "次交易" : "trades"} · {base.costBps} bps
            </p>
          </div>
          <div className="text-right text-[9.5px] leading-relaxed text-neutral-600">
            {zh ? "下一交易日入场 · 同标的最新观点覆盖 · 活跃标的等权" : "Next-day entry · latest call wins · equal-weight active tickers"}
          </div>
        </div>
      </header>

      <dl className="grid grid-cols-2 border-b border-line sm:grid-cols-4 xl:grid-cols-8">
        {metrics.map(([label, value, positive]) => (
          <div key={label} className="border-b border-r border-line/75 px-3 py-3 last:border-r-0 xl:border-b-0">
            <dt className="text-[8.5px] uppercase tracking-[0.08em] text-neutral-600">{label}</dt>
            <dd className={`mt-1.5 font-mono text-[14px] font-bold ${positive ? "text-bull" : value.startsWith("-") ? "text-bear" : "text-cream"}`}>
              {value}
            </dd>
          </div>
        ))}
      </dl>

      <div className="px-4 py-3">
        <div className="flex items-end justify-between">
          <div>
            <h3 className="text-[10.5px] font-semibold text-cream">
              {zh ? "累计净值（起点 = 100）" : "Cumulative equity (start = 100)"}
            </h3>
            <p className="mt-0.5 text-[9px] text-neutral-600">
              {zh
                ? `已计入往返 ${base.costBps} bps 成本；无有效观点时持有现金。`
                : `Includes ${base.costBps} bps round-trip cost; cash when inactive.`}
            </p>
          </div>
          <div className="font-mono text-[9.5px] text-neutral-600">
            {zh ? "活跃率" : "Exposure"} {(base.exposurePct * 100).toFixed(1)}% · {zh ? "平均持仓" : "Avg positions"} {base.averageActivePositions.toFixed(1)}
          </div>
        </div>
        <ReactECharts
          option={chartOption}
          style={{ height: 340, width: "100%" }}
          opts={{ renderer: "canvas" }}
          notMerge
        />
      </div>

      <div className="grid border-t border-line lg:grid-cols-[minmax(0,1.25fr)_minmax(300px,.75fr)]">
        <section className="border-b border-line lg:border-b-0 lg:border-r">
          <header className="border-b border-line/75 px-4 py-3">
            <h3 className="text-[10.5px] font-semibold text-cream">
              {zh ? "年度收益" : "Calendar-year returns"}
            </h3>
          </header>
          <div className="divide-y divide-line/75">
            {base.yearReturns.map((item) => (
              <div key={item.year} className="grid grid-cols-[56px_1fr_1fr] items-center gap-4 px-4 py-2.5 text-[10.5px]">
                <span className="font-mono font-semibold text-neutral-400">{item.year}</span>
                <span className="flex items-center justify-between gap-2">
                  <span className="text-neutral-600">{zh ? "组合" : "Portfolio"}</span>
                  <span className={`font-mono font-bold ${item.return >= 0 ? "text-bull" : "text-bear"}`}>{pct(item.return)}</span>
                </span>
                <span className="flex items-center justify-between gap-2">
                  <span className="text-neutral-600">SPY</span>
                  <span className={`font-mono ${item.benchmarkReturn >= 0 ? "text-neutral-300" : "text-bear"}`}>{pct(item.benchmarkReturn)}</span>
                </span>
              </div>
            ))}
          </div>
        </section>

        <section>
          <header className="border-b border-line/75 px-4 py-3">
            <h3 className="text-[10.5px] font-semibold text-cream">
              {zh ? "风险与稳健性" : "Risk and robustness"}
            </h3>
          </header>
          <dl className="grid grid-cols-2 gap-x-5 gap-y-3 px-4 py-3 text-[10px]">
            <div><dt className="text-neutral-600">Beta</dt><dd className="mt-1 font-mono font-bold text-cream">{number(base.beta)}</dd></div>
            <div><dt className="text-neutral-600">{zh ? "年化 Alpha" : "Annual alpha"}</dt><dd className={`mt-1 font-mono font-bold ${(base.annualizedAlpha ?? 0) >= 0 ? "text-bull" : "text-bear"}`}>{pct(base.annualizedAlpha)}</dd></div>
            <div><dt className="text-neutral-600">Calmar</dt><dd className="mt-1 font-mono font-bold text-cream">{number(base.calmar)}</dd></div>
            <div><dt className="text-neutral-600">{zh ? "活跃日胜率" : "Positive active days"}</dt><dd className="mt-1 font-mono font-bold text-cream">{pct(base.positiveActiveDayRate)}</dd></div>
            <div className="col-span-2 border-t border-line/75 pt-3">
              <dt className="text-neutral-600">{zh ? "最大回撤区间" : "Max drawdown period"}</dt>
              <dd className="mt-1 font-mono text-neutral-300">{base.drawdownPeakDay} → {base.drawdownTroughDay}</dd>
            </div>
          </dl>
          <div className="border-t border-line/75 px-4 py-3">
            <div className="text-[9px] uppercase tracking-[0.08em] text-neutral-600">{zh ? "成本敏感性" : "Cost sensitivity"}</div>
            <div className="mt-2 grid grid-cols-3 gap-2">
              {backtest.costSensitivity.map((item) => (
                <div key={item.costBps} className="border-l border-line pl-2">
                  <div className="font-mono text-[9px] text-neutral-600">{item.costBps} bps</div>
                  <div className="mt-1 font-mono text-[11px] font-bold text-cream">{pct(item.annualizedReturn)}</div>
                </div>
              ))}
            </div>
          </div>
        </section>
      </div>

      <footer className="border-t border-line px-4 py-3 text-[9.5px] leading-relaxed text-neutral-600">
        {zh
          ? "回测为等权信号跟随模型，不代表作者真实账户收益；未计税费、融券可得性、借券成本和市场冲击。Sharpe/Alpha 采用 0% 无风险利率。"
          : "This is an equal-weight signal-following model, not the author's actual account. Taxes, borrow availability, borrow fees and market impact are excluded; Sharpe/alpha use a 0% risk-free rate."}
      </footer>
    </section>
  );
}
