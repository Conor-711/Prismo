"use client";

import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { staticDataUrl } from "@/lib/site";
import { KolModule } from "./KolModule";
import { SmartVoiceTickerModule } from "@/features/smart-voice";
import { SmartVoiceTickerSignals } from "./SmartVoiceTickerSignals";
import type { KolCandle, KolTargetData } from "@/shared/market/mockDetail";
import type { DailyNet, DailyVol, RetailVol, WindowedArguments } from "@/server/queries/kolQueries";
import type { OverallData } from "@/server/queries/overallData";
import type { SvTickerBoard } from "@/features/smart-voice/svMock";
import type { SvTickerSignalData } from "@/server/queries/smartVoiceTickerSignals";

function InfoHint({ text }: { text: string }) {
  return (
    <span className="group relative inline-flex">
      <span
        tabIndex={0}
        aria-label={text}
        className="grid h-4 w-4 cursor-help place-items-center rounded-full text-[10px] font-bold text-neutral-500 ring-1 ring-inset ring-neutral-500/70 transition hover:text-cream hover:ring-neutral-300 focus:text-cream focus:outline-none focus:ring-neutral-300"
      >
        i
      </span>
      <span className="pointer-events-none absolute left-1/2 top-5 z-30 hidden w-72 -translate-x-1/2 rounded-lg bg-elevated px-3 py-2 text-[11px] font-normal leading-relaxed text-neutral-300 shadow-xl ring-1 ring-inset ring-line group-hover:block group-focus-within:block">
        {text}
      </span>
    </span>
  );
}

function MaximizeIcon({ minimized = false }: { minimized?: boolean }) {
  return (
    <svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      {minimized ? (
        <>
          <path d="M8 3v5H3" />
          <path d="M16 3v5h5" />
          <path d="M8 21v-5H3" />
          <path d="M16 21v-5h5" />
        </>
      ) : (
        <>
          <path d="M8 3H3v5" />
          <path d="M16 3h5v5" />
          <path d="M8 21H3v-5" />
          <path d="M16 21h5v-5" />
        </>
      )}
    </svg>
  );
}

type Props = {
  zh: boolean;
  symbol: string;
  flowDays: KolCandle[];
  sentiment?: DailyNet[];
  volume?: DailyVol[];
  retailSentiment?: DailyNet[];
  retailVolume?: RetailVol[];
  overall?: OverallData | null;
  targetPrices?: KolTargetData;
  argumentsData?: WindowedArguments;
  smartVoice?: SvTickerBoard | null;
  smartVoiceSignals?: SvTickerSignalData | null;
};

export function TickerOverviewPanel({
  zh,
  symbol,
  flowDays,
  sentiment,
  volume,
  retailSentiment,
  retailVolume,
  overall,
  targetPrices,
  argumentsData,
  smartVoice,
  smartVoiceSignals,
}: Props) {
  const [full, setFull] = useState(false);
  const [mounted, setMounted] = useState(false);
  const [dashboard, setDashboard] = useState<"market" | "sv">("market");
  const [loadedSignals, setLoadedSignals] = useState<SvTickerSignalData | null | undefined>(smartVoiceSignals);
  const signalsRequestedFor = useRef("");
  const overviewHint = zh
    ? "通过上方按钮切换市场数据与 SV 数据。市场数据展示近一年净情绪、讨论度、聪明钱与散户差异、目标价和股价；SV 数据专门展示优质投资者观点转向、变化广度、目标修正、价格背离及历史表现。"
    : "Use the header control to switch between market and SV dashboards. Market covers sentiment, discussion, smart-retail differences, targets and price; SV focuses on high-SV view shifts, breadth, target revisions, price divergence and historical outcomes.";

  useEffect(() => setMounted(true), []);
  useEffect(() => {
    setLoadedSignals(smartVoiceSignals);
    signalsRequestedFor.current = "";
  }, [smartVoiceSignals, symbol]);
  useEffect(() => {
    if (dashboard !== "sv" || smartVoiceSignals || signalsRequestedFor.current === symbol) return;
    signalsRequestedFor.current = symbol;
    const controller = new AbortController();
    fetch(staticDataUrl(`/data/smart-voice-ticker/${encodeURIComponent(symbol.toUpperCase())}`), {
      signal: controller.signal,
    })
      .then((response) => {
        if (!response.ok) throw new Error(`SV ticker export returned ${response.status}`);
        return response.json();
      })
      .then((payload: { data?: SvTickerSignalData | null }) => {
        setLoadedSignals(payload.data ?? null);
      })
      .catch((error: unknown) => {
        if (!(error instanceof DOMException && error.name === "AbortError")) {
          console.error("Failed to load ticker SV signals", error);
          setLoadedSignals(null);
        }
      });
    return () => controller.abort();
  }, [dashboard, smartVoiceSignals, symbol]);

  useEffect(() => {
    if (!full) return;
    const html = document.documentElement;
    const body = document.body;
    const prevHtml = html.style.overflow;
    const prevBody = body.style.overflow;
    html.style.overflow = "hidden";
    body.style.overflow = "hidden";
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") setFull(false);
    };
    window.addEventListener("keydown", onKey);
    return () => {
      html.style.overflow = prevHtml;
      body.style.overflow = prevBody;
      window.removeEventListener("keydown", onKey);
    };
  }, [full]);

  const dataModule = (
    <KolModule
      flowDays={flowDays}
      sentiment={sentiment}
      volume={volume}
      retailSentiment={retailSentiment}
      retailVolume={retailVolume}
      overall={overall}
      targetPrices={targetPrices}
      argumentsData={argumentsData}
    />
  );
  const resolvedSignals = smartVoiceSignals ?? loadedSignals;
  const smartVoiceModule = resolvedSignals ? (
    <SmartVoiceTickerSignals data={resolvedSignals} zh={zh} />
  ) : smartVoice ? (
    <SmartVoiceTickerModule board={smartVoice} zh={zh} />
  ) : null;
  const activeModule = dashboard === "sv" && smartVoiceModule ? smartVoiceModule : dataModule;

  const panelBody = (
    <>
      {activeModule}
      <p className="mt-3 border-t border-line/70 pt-2 text-[10.5px] text-neutral-600">
        {dashboard === "sv" && resolvedSignals
          ? (zh
              ? "SV 转向、变化广度、目标修正、价格-SV 背离和历史验证均来自真实 Call、历史时点 SV 与价格结算；SV 数字描述观点变化，不代表预期收益。"
              : "SV shift, breadth, target revisions, price-SV divergence and historical validation use real calls, point-in-time SV and price settlements; SV values describe view changes, not expected returns.")
          : dashboard === "sv"
            ? (zh ? "该标的暂未生成可用于变化分析的 SV 历史数据。" : "No SV history is available for change analysis on this ticker yet.")
            : (zh ? "异动 / 信号 / 风险等模块为演示数据（mock），用于展示模块设计；接入真实管线后替换。" : "Modules use mock demo data to showcase the design; to be wired to the real pipeline.")}
      </p>
    </>
  );

  return (
    <>
      <div className="flex h-full min-h-0 flex-col overflow-hidden rounded-xl bg-card/45 ring-1 ring-inset ring-line">
        <div className="flex shrink-0 items-center justify-between gap-3 border-b border-line px-4 py-3">
          <div className="min-w-0">
            <h2 className="flex items-center gap-1.5 font-display text-[15px] font-bold leading-none text-cream">
              {zh ? "整体数据" : "Overview"}
              <InfoHint text={overviewHint} />
            </h2>
          </div>
          <div className="flex shrink-0 items-center gap-2">
            <div className="flex rounded-md bg-elevated/55 p-0.5 ring-1 ring-inset ring-line" role="tablist" aria-label={zh ? "整体数据看板" : "Overview dashboards"}>
              {([
                ["market", zh ? "市场数据" : "Market"],
                ["sv", "SV"],
              ] as const).map(([value, label]) => {
                const disabled = value === "sv" && !smartVoiceModule;
                return (
                  <button
                    key={value}
                    type="button"
                    role="tab"
                    aria-selected={dashboard === value}
                    disabled={disabled}
                    onClick={() => setDashboard(value)}
                    className={`h-7 rounded px-2.5 text-[10.5px] font-semibold transition ${
                      dashboard === value
                        ? "bg-reddit/12 text-reddit ring-1 ring-inset ring-reddit/30"
                        : "text-neutral-500 hover:text-neutral-300 disabled:cursor-not-allowed disabled:opacity-35"
                    }`}
                  >
                    {label}
                  </button>
                );
              })}
            </div>
            <button
              type="button"
              onClick={() => setFull(true)}
              className="grid h-8 w-8 place-items-center rounded-md text-reddit ring-1 ring-inset ring-reddit/35 transition hover:bg-reddit/10 hover:text-cream"
              title={zh ? "进入全屏看板" : "Open fullscreen dashboard"}
              aria-label={zh ? "进入全屏看板" : "Open fullscreen dashboard"}
            >
              <MaximizeIcon />
            </button>
          </div>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto p-3">
          {panelBody}
        </div>
      </div>

      {mounted && full
        ? createPortal(
            <div className="fixed inset-0 z-[140] bg-ink text-cream">
              <div className="grid h-screen min-h-0 grid-rows-[auto_minmax(0,1fr)]">
                <div className="flex items-center justify-between gap-4 border-b border-line bg-surface px-5 py-3">
                  <div className="min-w-0">
                    <div className="text-[10px] font-bold uppercase tracking-[0.16em] text-reddit">Prismo</div>
                    <h2 className="mt-0.5 truncate font-display text-[18px] font-extrabold leading-none">
                      {dashboard === "sv"
                        ? (zh ? "SV 数据看板" : "SV Dashboard")
                        : (zh ? "市场数据看板" : "Market Dashboard")}
                    </h2>
                  </div>
                  <div className="flex items-center gap-2">
                    <div className="flex rounded-md bg-elevated/55 p-0.5 ring-1 ring-inset ring-line" role="tablist" aria-label={zh ? "整体数据看板" : "Overview dashboards"}>
                      {([
                        ["market", zh ? "市场数据" : "Market"],
                        ["sv", "SV"],
                      ] as const).map(([value, label]) => (
                        <button
                          key={value}
                          type="button"
                          role="tab"
                          aria-selected={dashboard === value}
                          disabled={value === "sv" && !smartVoiceModule}
                          onClick={() => setDashboard(value)}
                          className={`h-8 rounded px-3 text-[11px] font-semibold transition ${
                            dashboard === value
                              ? "bg-reddit/12 text-reddit ring-1 ring-inset ring-reddit/30"
                              : "text-neutral-500 hover:text-neutral-300 disabled:cursor-not-allowed disabled:opacity-35"
                          }`}
                        >
                          {label}
                        </button>
                      ))}
                    </div>
                    <button
                      type="button"
                      onClick={() => setFull(false)}
                      className="inline-flex h-9 items-center gap-2 rounded-md px-3 text-[12px] font-semibold text-neutral-300 ring-1 ring-inset ring-line transition hover:bg-white/[.05] hover:text-cream"
                    >
                      <MaximizeIcon minimized />
                      {zh ? "退出全屏" : "Exit fullscreen"}
                    </button>
                  </div>
                </div>
                <div className="min-h-0 overflow-y-auto p-4">
                  <div className="min-h-full min-w-0 rounded-xl bg-card/50 p-4 ring-1 ring-inset ring-line">
                    {dashboard === "sv" && !smartVoiceModule ? (
                      <div className="grid min-h-[420px] place-items-center text-sm text-neutral-600">
                        {zh ? "暂无 SV 变化数据" : "No SV change data"}
                      </div>
                    ) : activeModule}
                  </div>
                </div>
              </div>
            </div>,
            document.body
          )
        : null}
    </>
  );
}
