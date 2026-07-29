"use client";

import type { PrivateSmartVoiceCall } from "@/server/queries/privateSmartVoiceExperiment";

function signed(value: number | null) {
  if (value == null) return "—";
  const percent = value * 100;
  return `${percent >= 0 ? "+" : ""}${percent.toFixed(1)}%`;
}

function directionLabel(direction: PrivateSmartVoiceCall["direction"], zh: boolean) {
  if (direction === "bull") return zh ? "看多" : "Bull";
  if (direction === "bear") return zh ? "看空" : "Bear";
  return zh ? "中性" : "Neutral";
}

export function PrivateSmartVoiceCallTable({
  calls,
  zh,
}: {
  calls: PrivateSmartVoiceCall[];
  zh: boolean;
}) {
  const ordered = [...calls].sort((a, b) => b.day.localeCompare(a.day));
  return (
    <section className="border-t border-line">
      <header className="flex items-center justify-between px-4 py-3">
        <div>
          <h2 className="text-[11px] font-bold text-cream">
            {zh ? "可核验喊单记录" : "Verifiable call history"}
          </h2>
          <p className="mt-0.5 text-[9.5px] text-neutral-600">
            {zh ? "按发布时间倒序，结果均从下一交易日开始结算。" : "Newest first; outcomes enter on the next trading day."}
          </p>
        </div>
        <span className="font-mono text-[10px] text-neutral-600">{ordered.length}</span>
      </header>
      <div className="divide-y divide-line/75 border-t border-line/75">
        {ordered.map((call) => {
          const summary = (zh ? call.summaryZh : call.summaryEn) || call.summaryZh || call.summaryEn || call.evidence;
          const performance = call.excessReturnPct;
          return (
            <article
              key={`${call.candidateId}:${call.horizon}`}
              className="grid gap-2 px-4 py-3 hover:bg-white/[.018] sm:grid-cols-[96px_minmax(0,1fr)_120px]"
            >
              <div>
                <div className="font-mono text-[10px] text-neutral-500">{call.day}</div>
                <div className="mt-1.5 flex items-center gap-1.5">
                  <span className={`rounded-sm px-1.5 py-0.5 text-[9px] font-semibold ring-1 ring-inset ${
                    call.direction === "bull"
                      ? "bg-bull/10 text-bull ring-bull/25"
                      : "bg-bear/10 text-bear ring-bear/25"
                  }`}>
                    {directionLabel(call.direction, zh)}
                  </span>
                  <span className="font-mono text-[9px] text-neutral-600">{call.horizon}</span>
                </div>
              </div>
              <div className="min-w-0">
                <p className="text-[10.5px] leading-[1.55] text-neutral-400">{summary}</p>
                {call.evidence ? (
                  <p className="mt-1.5 border-l border-line pl-2 text-[9.5px] leading-[1.45] text-neutral-600">
                    “{call.evidence}”
                  </p>
                ) : null}
              </div>
              <div className="flex items-start justify-between gap-3 sm:block sm:text-right">
                <div>
                  <div className={`font-mono text-[11px] font-bold ${
                    performance != null && performance >= 0 ? "text-bull" : "text-bear"
                  }`}>
                    {signed(performance)}
                  </div>
                  <div className="mt-0.5 text-[9px] text-neutral-600">
                    {zh ? "方向超额" : "Directional excess"}
                  </div>
                </div>
                <a
                  href={call.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="mt-0 text-[9.5px] font-semibold text-reddit hover:text-cream sm:mt-2 sm:inline-block"
                >
                  {zh ? "打开原帖 ↗" : "Open source ↗"}
                </a>
              </div>
            </article>
          );
        })}
      </div>
    </section>
  );
}
