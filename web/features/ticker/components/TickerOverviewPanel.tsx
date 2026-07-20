"use client";

import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { KolModule } from "./KolModule";
import { SmartVoiceTickerModule } from "@/features/smart-voice";
import { SmartVoiceTickerSignals } from "./SmartVoiceTickerSignals";
import type { KolCandle, KolTargetData } from "@/shared/market/mockDetail";
import type { DailyNet, DailyVol, KolNew, RetailVol, RetailNew, WindowedArguments } from "@/server/queries/kolQueries";
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
  flowDays: KolCandle[];
  sentiment?: DailyNet[];
  volume?: DailyVol[];
  retailSentiment?: DailyNet[];
  retailVolume?: RetailVol[];
  retailNewcomers?: RetailNew[];
  kolNewcomers?: KolNew[];
  overall?: OverallData | null;
  targetPrices?: KolTargetData;
  argumentsData?: WindowedArguments;
  smartVoice?: SvTickerBoard | null;
  smartVoiceSignals?: SvTickerSignalData | null;
};

export function TickerOverviewPanel({
  zh,
  flowDays,
  sentiment,
  volume,
  retailSentiment,
  retailVolume,
  retailNewcomers,
  kolNewcomers,
  overall,
  targetPrices,
  argumentsData,
  smartVoice,
  smartVoiceSignals,
}: Props) {
  const [full, setFull] = useState(false);
  const [mounted, setMounted] = useState(false);
  const overviewHint = zh
    ? "展示该标的在近一年里的净情绪、讨论度、聪明钱减散户分歧差、新增参与者与拥挤度、观点视角多空分布、目标价分布，以及 AI 识别的异常波动归因。当前更早日期使用稳定 mock 补全，用于呈现一年尺度。"
    : "Shows one-year net sentiment, discussion volume, smart-money minus retail divergence, newcomers and crowding, viewpoint-by-stance distribution, target price distribution, and AI anomaly attribution. Earlier missing dates are filled with stable mock data for the one-year view.";

  useEffect(() => setMounted(true), []);

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
      retailNewcomers={retailNewcomers}
      kolNewcomers={kolNewcomers}
      overall={overall}
      targetPrices={targetPrices}
      argumentsData={argumentsData}
    />
  );
  const smartVoiceModule = smartVoiceSignals ? (
    <SmartVoiceTickerSignals data={smartVoiceSignals} board={smartVoice} zh={zh} />
  ) : smartVoice ? (
    <SmartVoiceTickerModule board={smartVoice} zh={zh} />
  ) : null;

  const panelBody = (
    <>
      {dataModule}
      {smartVoiceModule && <div className="mt-4">{smartVoiceModule}</div>}
      <p className="mt-3 border-t border-line/70 pt-2 text-[10.5px] text-neutral-600">
        {smartVoiceSignals
          ? (zh
              ? "SV 聚集、目标价、观点变化、分歧、仓位匹配和历史回测均来自真实 Call、历史时点 SV 与价格结算；整体数据中的早期缺口仍可能使用稳定补全值。"
              : "SV clusters, targets, opinion changes, divergence, position fit and backtests use real calls, point-in-time SV and price settlements; earlier gaps in the general overview may still use stable fills.")
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
            <button
              type="button"
              onClick={() => setFull(true)}
              className="grid h-8 w-8 place-items-center rounded-md text-reddit ring-1 ring-inset ring-reddit/35 transition hover:bg-reddit/10 hover:text-cream"
              title={zh ? "进入全屏看板" : "Open fullscreen dashboard"}
              aria-label={zh ? "进入全屏看板" : "Open fullscreen dashboard"}
            >
              <MaximizeIcon />
            </button>
            <span className="rounded-md bg-reddit/12 px-2 py-1 text-[11px] font-semibold text-reddit ring-1 ring-inset ring-reddit/25">
              {zh ? "Overview" : "Overview"}
            </span>
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
                      {zh ? "整体数据看板" : "Overview Dashboard"}
                    </h2>
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
                <div className="min-h-0 overflow-y-auto p-4">
                  <div className="grid min-h-full gap-4 xl:grid-cols-[minmax(0,1fr)_minmax(460px,0.8fr)]">
                    <div className="min-w-0 rounded-xl bg-card/50 p-4 ring-1 ring-inset ring-line">
                      {dataModule}
                    </div>
                    <div className="min-w-0">
                      {smartVoiceModule ? (
                        smartVoiceModule
                      ) : (
                        <div className="rounded-xl bg-card/45 p-6 text-sm text-neutral-600 ring-1 ring-inset ring-line">
                          {zh ? "暂无 SV 投资者数据" : "No SV investor data"}
                        </div>
                      )}
                    </div>
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
