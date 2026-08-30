"use client";

import { useMemo, useState } from "react";
import type {
  HyperliquidCategory,
  HyperliquidMarket,
  HyperliquidMarketSignal,
  HyperliquidSmartMoneyData,
  HyperliquidWindow,
} from "../hyperliquidData";

type SortKey = "signal" | "flow" | "volume";

const CATEGORY_OPTIONS: { key: "all" | HyperliquidCategory; zh: string; en: string }[] = [
  { key: "all", zh: "全部", en: "All" },
  { key: "stocks", zh: "股票", en: "Stocks" },
  { key: "indices", zh: "指数", en: "Indices" },
  { key: "commodities", zh: "商品", en: "Commodities" },
  { key: "fx", zh: "外汇", en: "FX" },
  { key: "preipo", zh: "未上市", en: "Pre-IPO" },
];

function compactMoney(value: number) {
  const sign = value < 0 ? "-" : value > 0 ? "+" : "";
  const absolute = Math.abs(value);
  if (absolute >= 1_000_000_000) return `${sign}$${(absolute / 1_000_000_000).toFixed(1)}B`;
  if (absolute >= 1_000_000) return `${sign}$${(absolute / 1_000_000).toFixed(1)}M`;
  if (absolute >= 1_000) return `${sign}$${(absolute / 1_000).toFixed(1)}K`;
  return `${sign}$${absolute.toFixed(0)}`;
}

function compactUnsignedMoney(value: number) {
  return compactMoney(Math.abs(value)).replace("+$", "$");
}

function shortAddress(address: string) {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

function directionLabel(signal: HyperliquidMarketSignal["signal"], zh: boolean) {
  const labels = {
    bullish: ["净多", "Net long"],
    bearish: ["净空", "Net short"],
    mixed: ["分歧", "Mixed"],
    insufficient: ["样本不足", "Low sample"],
  } as const;
  return labels[signal][zh ? 0 : 1];
}

function signalTone(signal: HyperliquidMarketSignal["signal"]) {
  if (signal === "bullish") return "text-bull";
  if (signal === "bearish") return "text-bear";
  return "text-neutral-500";
}

function marketSignal(market: HyperliquidMarket, windowKey: HyperliquidWindow) {
  return market.signals[windowKey] ?? null;
}

function ConsensusBar({ value }: { value: number }) {
  const normalized = Math.max(-1, Math.min(1, value));
  const width = Math.abs(normalized) * 50;
  return (
    <div className="relative h-2 overflow-hidden rounded-sm bg-white/[.04]">
      <span className="absolute inset-y-0 left-1/2 w-px bg-neutral-600" />
      <span
        className={`absolute inset-y-0 ${normalized >= 0 ? "left-1/2 bg-bull" : "right-1/2 bg-bear"}`}
        style={{ width: `${width}%` }}
      />
    </div>
  );
}

function FlowBars({ signal }: { signal: HyperliquidMarketSignal }) {
  const values = signal.dailyFlow.slice(-7);
  const max = Math.max(...values.map((row) => Math.abs(row.value)), 1);
  return (
    <div className="flex h-16 items-end gap-1 border-b border-line/70 px-1" aria-label="Seven day smart-money flow">
      {values.length ? values.map((row) => {
        const height = Math.max(3, Math.abs(row.value) / max * 48);
        return (
          <span key={row.day} title={`${row.day} ${compactMoney(row.value)}`} className="flex min-w-0 flex-1 items-end justify-center">
            <span className={`w-full max-w-5 rounded-t-[1px] ${row.value >= 0 ? "bg-bull/80" : "bg-bear/80"}`} style={{ height }} />
          </span>
        );
      }) : <span className="self-center text-[10px] text-neutral-700">No flow observations</span>}
    </div>
  );
}

export function HyperliquidSmartMoneyView({ data, zh }: { data: HyperliquidSmartMoneyData; zh: boolean }) {
  const [category, setCategory] = useState<"all" | HyperliquidCategory>("stocks");
  const [windowKey, setWindowKey] = useState<HyperliquidWindow>("7");
  const [sortKey, setSortKey] = useState<SortKey>("signal");
  const [query, setQuery] = useState("");
  const filtered = useMemo(() => {
    const normalizedQuery = query.trim().toUpperCase();
    return data.markets
      .filter((market) => category === "all" || market.category === category)
      .filter((market) => !normalizedQuery || market.symbol.includes(normalizedQuery) || market.venues.some((venue) => venue.toUpperCase().includes(normalizedQuery)))
      .filter((market) => Boolean(marketSignal(market, windowKey)))
      .sort((left, right) => {
        const leftSignal = marketSignal(left, windowKey)!;
        const rightSignal = marketSignal(right, windowKey)!;
        if (sortKey === "flow") return Math.abs(rightSignal.weightedFlow) - Math.abs(leftSignal.weightedFlow);
        if (sortKey === "volume") return right.dayVolume - left.dayVolume;
        const leftStrength = leftSignal.qualifiedWallets >= 3 ? 2 + Math.abs(leftSignal.consensus) : leftSignal.qualifiedWallets > 0 ? 1 + Math.abs(leftSignal.consensus) * 0.1 : 0;
        const rightStrength = rightSignal.qualifiedWallets >= 3 ? 2 + Math.abs(rightSignal.consensus) : rightSignal.qualifiedWallets > 0 ? 1 + Math.abs(rightSignal.consensus) * 0.1 : 0;
        return rightStrength - leftStrength || right.dayVolume - left.dayVolume;
      });
  }, [category, data.markets, query, sortKey, windowKey]);
  const [selectedKey, setSelectedKey] = useState("");
  const selected = filtered.find((market) => `${market.category}:${market.symbol}` === selectedKey) ?? filtered[0] ?? null;
  const selectedSignal = selected ? marketSignal(selected, windowKey) : null;

  if (!data.markets.length) {
    return (
      <div className="grid h-full place-items-center p-8 text-center">
        <div>
          <div className="font-display text-base font-bold text-cream">{zh ? "暂无 Hyperliquid TradFi 数据" : "No Hyperliquid TradFi data"}</div>
          <p className="mt-2 text-[11px] text-neutral-500">
            {zh ? "运行 make hyperliquid-smart-money 建立地址池并导出第一版 Onchain Score。" : "Run make hyperliquid-smart-money to build the wallet pool and export Onchain Score."}
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="grid h-full min-h-0 grid-rows-[44px_minmax(0,1fr)]">
      <div className="flex min-w-0 items-center gap-2 border-b border-line px-3">
        <div className="flex shrink-0 items-center rounded-md bg-black/15 p-0.5 ring-1 ring-inset ring-line">
          {CATEGORY_OPTIONS.map((option) => (
            <button
              key={option.key}
              type="button"
              onClick={() => setCategory(option.key)}
              className={`h-7 rounded px-2.5 text-[10px] font-semibold transition ${category === option.key ? "bg-reddit/12 text-reddit ring-1 ring-inset ring-reddit/35" : "text-neutral-500 hover:text-cream"}`}
            >
              {zh ? option.zh : option.en}
            </button>
          ))}
        </div>
        <input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder={zh ? "搜索标的或 DEX" : "Search asset or DEX"}
          className="h-7 min-w-24 max-w-56 flex-1 rounded-md bg-black/15 px-2.5 text-[10.5px] text-cream outline-none ring-1 ring-inset ring-line placeholder:text-neutral-700 focus:ring-reddit/40"
        />
        <span
          className="hidden shrink-0 text-[8.5px] text-neutral-700 min-[1120px]:inline"
          title={zh ? "高分地址来自合格方向性地址的前 25%，低样本分数向 50 收缩；算法型和截断地址不进入榜单。" : "Smart wallets are the top quartile of qualified directional wallets. Low samples shrink toward 50; algorithmic and truncated accounts are excluded."}
        >
          {zh ? `观察 ${data.summary.observedWalletCount} · 合格 ${data.summary.qualifiedWalletCount} · 高分 ${data.summary.smartWalletCount}` : `${data.summary.observedWalletCount} observed · ${data.summary.qualifiedWalletCount} qualified · ${data.summary.smartWalletCount} smart`}
        </span>
        <div className="ml-auto flex shrink-0 items-center gap-2">
          <div className="flex rounded-md p-0.5 ring-1 ring-inset ring-line">
            {(["signal", "flow", "volume"] as SortKey[]).map((key) => (
              <button key={key} type="button" onClick={() => setSortKey(key)} className={`h-6 rounded px-2 text-[9.5px] ${sortKey === key ? "bg-white/[.06] text-cream" : "text-neutral-600"}`}>
                {key === "signal" ? (zh ? "共识" : "Consensus") : key === "flow" ? (zh ? "资金流" : "Flow") : (zh ? "成交量" : "Volume")}
              </button>
            ))}
          </div>
          <div className="flex rounded-md p-0.5 ring-1 ring-inset ring-line">
            {(["1", "3", "7"] as HyperliquidWindow[]).map((key) => (
              <button key={key} type="button" onClick={() => setWindowKey(key)} className={`h-6 rounded px-2 text-[9.5px] font-mono ${windowKey === key ? "bg-reddit/12 text-reddit ring-1 ring-inset ring-reddit/30" : "text-neutral-600"}`}>
                {key}D
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="grid min-h-0 grid-cols-[minmax(380px,0.84fr)_minmax(0,1.36fr)]">
        <section className="grid min-h-0 grid-rows-[34px_minmax(0,1fr)] border-r border-line">
          <div className="grid grid-cols-[minmax(120px,1fr)_88px_92px_92px] items-center border-b border-line px-3 text-[9px] font-semibold uppercase text-neutral-700">
            <span>{zh ? "TradFi 标的" : "TradFi asset"}</span>
            <span className="text-right">{zh ? "方向" : "Direction"}</span>
            <span className="text-right">{zh ? "地址" : "Wallets"}</span>
            <span className="text-right">{zh ? "净流" : "Net flow"}</span>
          </div>
          <div className="min-h-0 overflow-y-auto">
            {filtered.map((market) => {
              const signal = marketSignal(market, windowKey)!;
              const key = `${market.category}:${market.symbol}`;
              const active = selected ? key === `${selected.category}:${selected.symbol}` : false;
              return (
                <button
                  key={key}
                  type="button"
                  onClick={() => setSelectedKey(key)}
                  className={`grid h-[58px] w-full grid-cols-[minmax(120px,1fr)_88px_92px_92px] items-center border-b border-line/80 px-3 text-left transition ${active ? "bg-reddit/[.07] shadow-[inset_2px_0_0_#57D7BA]" : "hover:bg-white/[.025]"}`}
                >
                  <span className="min-w-0">
                    <span className="flex items-baseline gap-2"><strong className="font-mono text-[12px] text-cream">{market.symbol}</strong><span className="truncate text-[9px] uppercase text-neutral-700">{market.venues.join(" · ")}</span></span>
                    <span className="mt-1 block truncate font-mono text-[9.5px] text-neutral-600">${market.markPrice.toLocaleString(undefined, { maximumFractionDigits: 3 })} · {compactUnsignedMoney(market.dayVolume)}</span>
                  </span>
                  <span className={`text-right text-[10.5px] font-semibold ${signalTone(signal.signal)}`}>{directionLabel(signal.signal, zh)}</span>
                  <span className="text-right font-mono text-[10.5px] text-neutral-400"><span className="text-bull">{signal.longWallets}</span><span className="px-1 text-neutral-700">/</span><span className="text-bear">{signal.shortWallets}</span></span>
                  <span className={`text-right font-mono text-[10px] ${signal.weightedFlow >= 0 ? "text-bull" : "text-bear"}`}>{compactMoney(signal.weightedFlow)}</span>
                </button>
              );
            })}
          </div>
        </section>

        {selected && selectedSignal ? (
          <section className="grid min-h-0 grid-rows-[auto_104px_minmax(0,1fr)]">
            <header className="border-b border-line px-4 py-3">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <div className="flex items-center gap-2"><h2 className="font-display text-[18px] font-bold leading-none text-cream">{selected.symbol}</h2><span className="rounded bg-white/[.04] px-1.5 py-0.5 text-[8.5px] uppercase text-neutral-500">Hyperliquid HIP-3</span></div>
                  <div className="mt-1.5 text-[9.5px] text-neutral-600">{selected.coins.join(" · ")}</div>
                </div>
                <div className="text-right"><div className="font-mono text-[18px] font-bold leading-none text-cream">${selected.markPrice.toLocaleString(undefined, { maximumFractionDigits: 4 })}</div><div className="mt-1.5 text-[9px] text-neutral-600">{zh ? "跨 DEX 成交量" : "Cross-DEX volume"} {compactUnsignedMoney(selected.dayVolume)}</div></div>
              </div>
              <div className="mt-3 grid grid-cols-5 divide-x divide-line rounded-md ring-1 ring-inset ring-line">
                {[
                  [zh ? "聪明钱方向" : "Smart direction", directionLabel(selectedSignal.signal, zh), signalTone(selectedSignal.signal)],
                  [zh ? "共识强度" : "Consensus", selectedSignal.qualifiedWallets >= 3 ? `${selectedSignal.consensus > 0 ? "+" : ""}${Math.round(selectedSignal.consensus * 100)}%` : (zh ? "待确认" : "Pending"), selectedSignal.qualifiedWallets >= 3 ? (selectedSignal.consensus >= 0 ? "text-bull" : "text-bear") : "text-neutral-500"],
                  [zh ? "高分地址" : "Smart wallets", String(selectedSignal.qualifiedWallets), "text-cream"],
                  [zh ? "净仓位" : "Net position", compactMoney(selectedSignal.netPositionNotional), selectedSignal.netPositionNotional >= 0 ? "text-bull" : "text-bear"],
                  [`${windowKey}D ${zh ? "净流" : "flow"}`, compactMoney(selectedSignal.weightedFlow), selectedSignal.weightedFlow >= 0 ? "text-bull" : "text-bear"],
                ].map(([label, value, tone]) => (
                  <div key={label} className="px-2.5 py-2"><div className="text-[8.5px] text-neutral-600">{label}</div><div className={`mt-1 font-mono text-[12px] font-bold ${tone}`}>{value}</div></div>
                ))}
              </div>
            </header>

            <div className="grid grid-cols-[minmax(0,1fr)_220px] gap-4 border-b border-line px-4 py-3">
              <div>
                <div className="flex items-center justify-between text-[9px] text-neutral-600"><span>{zh ? "高分地址仓位共识" : "High-score position consensus"}</span><span className="font-mono"><span className="text-bear">{selectedSignal.shortWallets} short</span> · <span className="text-bull">{selectedSignal.longWallets} long</span></span></div>
                <div className="mt-2"><ConsensusBar value={selectedSignal.qualifiedWallets >= 3 ? selectedSignal.consensus : 0} /></div>
                <div className="mt-2 flex justify-between font-mono text-[8.5px] text-neutral-700"><span>-100%</span><span>0</span><span>+100%</span></div>
              </div>
              <div><div className="text-[9px] text-neutral-600">{zh ? "每日加权净流" : "Daily weighted flow"}</div><FlowBars signal={selectedSignal} /></div>
            </div>

            <div className="grid min-h-0 grid-cols-[minmax(0,1fr)_minmax(300px,0.9fr)]">
              <div className="grid min-h-0 grid-rows-[32px_minmax(0,1fr)] border-r border-line">
                <div className="flex items-center justify-between border-b border-line px-4"><h3 className="text-[10.5px] font-bold text-cream">{zh ? "头部链上地址" : "Top onchain wallets"}</h3><span className="text-[8.5px] text-neutral-700">Onchain Score 0–100</span></div>
                <div className="min-h-0 overflow-y-auto">
                  {selectedSignal.topWallets.map((wallet) => (
                    <a key={`${wallet.address}:${wallet.coin}`} href={`https://app.hyperliquid.xyz/explorer/address/${wallet.address}`} target="_blank" rel="noreferrer" className="grid min-h-[52px] grid-cols-[minmax(100px,1fr)_62px_86px] items-center border-b border-line/70 px-4 transition hover:bg-white/[.025]">
                      <span className="min-w-0"><span className="block font-mono text-[10.5px] text-neutral-300">{shortAddress(wallet.address)}</span><span className="mt-1 block truncate text-[8.5px] text-neutral-700">{wallet.coin} · {wallet.lastAction}</span></span>
                      <span className="text-right"><span className="block font-mono text-[12px] font-bold text-reddit">{wallet.score.toFixed(1)}</span><span className="text-[8px] text-neutral-700">{Math.round(wallet.confidence * 100)}% conf.</span></span>
                      <span className={`text-right font-mono text-[10.5px] ${wallet.direction === "long" ? "text-bull" : "text-bear"}`}>{compactMoney(wallet.notional)}</span>
                    </a>
                  ))}
                  {!selectedSignal.topWallets.length ? <div className="p-5 text-center text-[10px] text-neutral-700">{zh ? "当前样本不足" : "Insufficient current sample"}</div> : null}
                </div>
              </div>
              <div className="grid min-h-0 grid-rows-[32px_minmax(0,1fr)]">
                <div className="flex items-center justify-between border-b border-line px-4"><h3 className="text-[10.5px] font-bold text-cream">{zh ? "真实成交证据" : "Fill evidence"}</h3><span className="text-[8.5px] text-neutral-700">{windowKey}D</span></div>
                <div className="min-h-0 overflow-y-auto">
                  {selectedSignal.evidence.map((evidence) => (
                    <a key={`${evidence.address}:${evidence.hash}:${evidence.time}`} href={`https://app.hyperliquid.xyz/explorer/tx/${evidence.hash}`} target="_blank" rel="noreferrer" className="block border-b border-line/70 px-4 py-2.5 transition hover:bg-white/[.025]">
                      <div className="flex items-center justify-between gap-3"><span className="font-mono text-[9.5px] text-neutral-400">{shortAddress(evidence.address)}</span><span className={`text-[9.5px] font-semibold ${evidence.side === "buy" ? "text-bull" : "text-bear"}`}>{evidence.action}</span></div>
                      <div className="mt-1.5 flex items-center justify-between font-mono text-[9px] text-neutral-600"><span>{evidence.coin} @ ${evidence.price.toLocaleString()}</span><span>{compactMoney(evidence.notional)}</span></div>
                      <div className="mt-1 text-[8px] text-neutral-700">{evidence.time.slice(0, 16).replace("T", " ")} UTC ↗</div>
                    </a>
                  ))}
                  {!selectedSignal.evidence.length ? <div className="p-5 text-center text-[10px] text-neutral-700">{zh ? "该窗口暂无高分地址成交" : "No high-score fills in this window"}</div> : null}
                </div>
              </div>
            </div>
          </section>
        ) : <div className="grid place-items-center text-[11px] text-neutral-600">{zh ? "没有符合当前筛选的市场" : "No markets match these filters"}</div>}
      </div>
    </div>
  );
}
