"use client";

import { TickerLogo } from "@/shared/market/TickerLogo";
import type { PrivateSmartVoiceTicker } from "@/server/queries/privateSmartVoiceExperiment";

export type PrivateTickerSort = "calls" | "excess" | "hit";

function signed(value: number) {
  return `${value >= 0 ? "+" : ""}${value.toFixed(1)}%`;
}

export function PrivateSmartVoiceTickerRail({
  tickers,
  selectedTicker,
  query,
  sort,
  onQueryChange,
  onSortChange,
  onSelect,
  zh,
}: {
  tickers: PrivateSmartVoiceTicker[];
  selectedTicker: string;
  query: string;
  sort: PrivateTickerSort;
  onQueryChange: (value: string) => void;
  onSortChange: (value: PrivateTickerSort) => void;
  onSelect: (ticker: string) => void;
  zh: boolean;
}) {
  return (
    <aside className="flex h-full min-h-0 flex-col border-b border-line lg:border-b-0 lg:border-r">
      <div className="shrink-0 border-b border-line p-3">
        <label className="flex h-8 items-center gap-2 rounded-md px-2.5 ring-1 ring-inset ring-line focus-within:ring-reddit/50">
          <span aria-hidden className="text-[13px] text-neutral-600">⌕</span>
          <input
            value={query}
            onChange={(event) => onQueryChange(event.target.value)}
            placeholder={zh ? "搜索标的" : "Search ticker"}
            className="min-w-0 flex-1 bg-transparent text-[11.5px] text-cream outline-none placeholder:text-neutral-700"
          />
        </label>
        <div className="mt-2 grid grid-cols-3 gap-1 rounded-md bg-white/[.025] p-0.5 ring-1 ring-inset ring-line">
          {([
            ["calls", zh ? "观点数" : "Calls"],
            ["excess", zh ? "超额" : "Excess"],
            ["hit", zh ? "命中" : "Hit rate"],
          ] as [PrivateTickerSort, string][]).map(([key, label]) => (
            <button
              key={key}
              type="button"
              onClick={() => onSortChange(key)}
              className={`h-7 rounded-sm text-[10.5px] font-semibold transition ${
                sort === key
                  ? "bg-reddit/12 text-reddit ring-1 ring-inset ring-reddit/30"
                  : "text-neutral-600 hover:text-cream"
              }`}
            >
              {label}
            </button>
          ))}
        </div>
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto">
        {tickers.map((item, index) => {
          const selected = item.ticker === selectedTicker;
          return (
            <button
              key={item.ticker}
              type="button"
              onClick={() => onSelect(item.ticker)}
              className={`grid w-full grid-cols-[24px_34px_minmax(0,1fr)_auto] items-center gap-2 border-b border-line/75 px-3 py-2.5 text-left transition ${
                selected
                  ? "bg-reddit/[.055] shadow-[inset_2px_0_0_#57D7BA]"
                  : "hover:bg-white/[.025]"
              }`}
            >
              <span className="font-mono text-[9.5px] text-neutral-700">
                {String(index + 1).padStart(2, "0")}
              </span>
              <TickerLogo ticker={item.ticker} size={32} />
              <span className="min-w-0">
                <span className="block truncate font-mono text-[12px] font-bold text-cream">
                  {item.ticker}
                </span>
                <span className="mt-0.5 block truncate text-[9.5px] text-neutral-600">
                  {item.settledCalls} {zh ? "条" : "calls"} · {item.bullCalls}/{item.bearCalls}
                </span>
              </span>
              <span className="text-right">
                <span
                  className={`block font-mono text-[11px] font-bold ${
                    item.meanDirectionalSpyExcessPct >= 0 ? "text-bull" : "text-bear"
                  }`}
                >
                  {signed(item.meanDirectionalSpyExcessPct)}
                </span>
                <span className="mt-0.5 block font-mono text-[9px] text-neutral-600">
                  {(item.hitRate * 100).toFixed(0)}%
                </span>
              </span>
            </button>
          );
        })}
      </div>
    </aside>
  );
}
