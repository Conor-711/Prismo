"use client";

import { useEffect, useState } from "react";
import { BASE_PATH } from "@/lib/site";
import type { KolCandle, KolTargetData } from "@/shared/market/mockDetail";
import type { DailyNet, DailyVol, RetailVol, WindowedArguments } from "@/server/queries/kolQueries";
import type { OverallData } from "@/server/queries/overallData";
import type { SvTickerBoard } from "@/features/smart-voice/svMock";
import { TickerOverviewPanel } from "./TickerOverviewPanel";

type OverviewPayload = {
  sentiment: DailyNet[];
  volume: DailyVol[];
  retailSentiment: DailyNet[];
  retailVolume: RetailVol[];
  overall: OverallData | null;
  targetPrices: KolTargetData;
  argumentsData: WindowedArguments;
};

function OverviewSkeleton() {
  return (
    <div className="flex h-full min-h-0 flex-col overflow-hidden rounded-xl bg-card/45 ring-1 ring-inset ring-line">
      <div className="flex h-[53px] shrink-0 items-center justify-between border-b border-line px-4">
        <div className="h-4 w-24 animate-pulse rounded bg-elevated" />
        <div className="h-7 w-32 animate-pulse rounded bg-elevated" />
      </div>
      <div className="grid min-h-0 flex-1 grid-rows-[minmax(0,1fr)_112px] gap-3 p-3">
        <div className="animate-pulse rounded-lg bg-elevated/70" />
        <div className="grid grid-cols-3 gap-3">
          <div className="animate-pulse rounded-lg bg-elevated/70" />
          <div className="animate-pulse rounded-lg bg-elevated/70" />
          <div className="animate-pulse rounded-lg bg-elevated/70" />
        </div>
      </div>
    </div>
  );
}

export function TickerOverviewLoader({
  symbol,
  zh,
  flowDays,
  smartVoice,
}: {
  symbol: string;
  zh: boolean;
  flowDays: KolCandle[];
  smartVoice?: SvTickerBoard | null;
}) {
  const [payload, setPayload] = useState<{ symbol: string; data: OverviewPayload } | null>(null);

  useEffect(() => {
    const controller = new AbortController();
    fetch(`${BASE_PATH}/data/ticker-overview/${encodeURIComponent(symbol.toUpperCase())}/`, {
      signal: controller.signal,
    })
      .then((response) => {
        if (!response.ok) throw new Error(`Ticker overview export returned ${response.status}`);
        return response.json();
      })
      .then((data: OverviewPayload) => setPayload({ symbol, data }))
      .catch((error: unknown) => {
        if (!(error instanceof DOMException && error.name === "AbortError")) {
          console.error("Failed to load ticker overview", error);
        }
      });
    return () => controller.abort();
  }, [symbol]);

  if (!payload || payload.symbol !== symbol) return <OverviewSkeleton />;
  const data = payload.data;
  return (
    <TickerOverviewPanel
      zh={zh}
      symbol={symbol}
      flowDays={flowDays}
      sentiment={data.sentiment}
      volume={data.volume}
      retailSentiment={data.retailSentiment}
      retailVolume={data.retailVolume}
      overall={data.overall}
      targetPrices={data.targetPrices}
      argumentsData={data.argumentsData}
      smartVoice={smartVoice}
    />
  );
}
