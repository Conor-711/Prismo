import { LocaleLink } from "@/components/i18n/LocaleLink";
import { TickerLogo } from "@/shared/market/TickerLogo";
import type { SmartVoiceMarketSource, SmartVoiceMarketWindow, SmartVoiceTickerEvidence, SmartVoiceTickerRank } from "@/server/queries/smartVoiceQueries";
import {
  evidenceGroups,
  highRatio,
  metricText,
  signalLabel,
  signed,
  signedInteger,
  type MarketMode,
} from "../smartVoiceMarketModel";

function evidenceLinkLabel(source: string, zh: boolean) {
  if (!zh) return source === "youtube" ? "Open video" : "Open original";
  return source === "youtube" ? "打开视频" : "打开原帖";
}

function EvidenceItem({ evidence, zh }: { evidence: SmartVoiceTickerEvidence; zh: boolean }) {
  const summary = (zh ? evidence.summaryZh : evidence.summaryEn) || evidence.originalEvidence;
  const showOriginal = evidence.originalEvidence && evidence.originalEvidence.trim() !== summary.trim();
  return (
    <article className="border-t border-line/70 py-2.5 first:border-t-0">
      <div className="flex min-w-0 items-center gap-1.5 text-[9.5px]">
        <span className="font-semibold uppercase text-neutral-400">{evidence.source}</span>
        <span className="truncate text-neutral-500">@{evidence.author.replace(/^@/, "")}</span>
        <span className="ml-auto shrink-0 font-mono text-neutral-600">Score {evidence.platformSv.toFixed(1)}</span>
      </div>
      <p className="mt-1.5 line-clamp-3 text-[10.5px] leading-[1.45] text-neutral-300">{summary}</p>
      {showOriginal ? (
        <p className="mt-1.5 line-clamp-2 border-l-2 border-white/10 pl-2 text-[9.5px] leading-[1.45] text-neutral-500">
          {zh ? "原文证据：" : "Original: "}{evidence.originalEvidence}
        </p>
      ) : null}
      <div className="mt-1.5 flex items-center justify-between gap-2 font-mono text-[9px] text-neutral-600">
        <span>{evidence.createdAt.slice(0, 10)} · {evidence.horizon || "unknown"}</span>
        <a
          href={evidence.url}
          target="_blank"
          rel="noreferrer"
          className="font-sans font-semibold text-reddit transition hover:text-cream"
        >
          {evidenceLinkLabel(evidence.source, zh)} ↗
        </a>
      </div>
    </article>
  );
}

export function SmartVoiceMarketDetail({
  selected,
  mode,
  windowKey,
  sources,
  latestAt,
  evidenceById,
  color,
  zh,
}: {
  selected: SmartVoiceTickerRank | undefined;
  mode: MarketMode;
  windowKey: SmartVoiceMarketWindow;
  sources: SmartVoiceMarketSource[];
  latestAt: string;
  evidenceById: Record<string, SmartVoiceTickerEvidence>;
  color: string;
  zh: boolean;
}) {
  if (!selected) {
    return <aside data-testid="smart-voice-market-detail" className="min-h-0 border-l border-line bg-white/[.012]" />;
  }

  const selectedEvidence = evidenceGroups(selected, mode);
  const primaryEvidence = selectedEvidence.primary
    .map((id) => evidenceById[id])
    .filter((item): item is SmartVoiceTickerEvidence => Boolean(item));
  const counterEvidence = selectedEvidence.counter
    .map((id) => evidenceById[id])
    .filter((item): item is SmartVoiceTickerEvidence => Boolean(item));

  return (
    <aside data-testid="smart-voice-market-detail" className="min-h-0 overflow-y-auto border-l border-line bg-white/[.012] p-4">
      <div className="flex min-h-full flex-col">
        <div className="flex items-start gap-3">
          <TickerLogo ticker={selected.ticker} size={38} />
          <div className="min-w-0 flex-1">
            <div className="font-mono text-[18px] font-bold leading-none text-cream">{selected.ticker}</div>
            <div className="mt-1 truncate text-[11px] text-neutral-500">{zh ? selected.nameZh : selected.nameEn}</div>
            <div className="mt-1 font-mono text-[9px] text-neutral-700">{windowKey} · {sources.join("+")} · {latestAt.slice(0, 16)} UTC</div>
          </div>
          <div className="text-right">
            <div className="text-[9px] uppercase tracking-[0.12em] text-neutral-600">
              {mode === "newCoverage"
                ? (zh ? "新增作者" : "New voices")
                : mode === "contrast" ? "Delta" : mode === "authorShift" ? (zh ? "突变幅度" : "Author shift") : (zh ? "高 Score 净强度" : "High-Score net")}
            </div>
            <div className="mt-1 font-mono text-[22px] font-bold leading-none" style={{ color }}>{metricText(selected, mode)}</div>
          </div>
        </div>

        <div className="mt-5 border-y border-line py-3">
          <div className="flex items-center justify-between text-[11px]">
            <span className="text-neutral-500">{mode === "newCoverage"
              ? (zh ? "新覆盖结构" : "New-coverage structure")
              : mode === "contrast"
                ? (zh ? "分歧关系" : "Divergence")
                : mode === "authorShift" ? (zh ? "作者净人数变化" : "Net-author change") : (zh ? "Top 10% 作者方向" : "Top 10% direction")}</span>
            <span className={`font-semibold ${mode === "authorShift" && selected.authorNetAbrupt ? "text-[#8CBBFF]" : "text-cream"}`}>
              {mode === "newCoverage"
                ? selected.cohortNew
                  ? (zh ? "首次进入高 Score 视野" : "New to high-Score cohort")
                  : selected.newCoverageAuthorCount >= 2
                    ? (zh ? "多位作者同步首提" : "Multiple new voices")
                    : (zh ? "单一作者首次覆盖" : "One new voice")
                : mode === "authorShift" ? (selected.authorNetAbrupt ? (zh ? "发生突变" : "Abrupt shift") : (zh ? "一般变化" : "Normal change")) : signalLabel(selected.signal, zh)}
            </span>
          </div>
          {mode === "newCoverage" ? (
            <div className="mt-3 grid grid-cols-3 gap-3 font-mono text-[10.5px]">
              <div>
                <span className="text-neutral-600">{zh ? "新增看多" : "New bull"}</span>
                <div className="mt-1 text-[14px] font-bold text-bull">{selected.newCoverageBullCount}</div>
              </div>
              <div>
                <span className="text-neutral-600">{zh ? "新增看空" : "New bear"}</span>
                <div className="mt-1 text-[14px] font-bold text-bear">{selected.newCoverageBearCount}</div>
              </div>
              <div>
                <span className="text-neutral-600">{zh ? "新增占比" : "New share"}</span>
                <div className="mt-1 text-[14px] font-bold text-[#8CBBFF]">{selected.newCoverageRatio.toFixed(1)}%</div>
              </div>
            </div>
          ) : mode === "contrast" ? (
            <div className="mt-3 grid grid-cols-2 gap-3 font-mono text-[10.5px]">
              <div><span className="text-neutral-600">Top 10%</span><div className={`mt-1 text-[14px] font-bold ${selected.highNet >= 0 ? "text-bull" : "text-bear"}`}>{signed(selected.highNet)}</div></div>
              <div><span className="text-neutral-600">Bottom 10%</span><div className={`mt-1 text-[14px] font-bold ${selected.lowNet >= 0 ? "text-bull" : "text-bear"}`}>{signed(selected.lowNet)}</div></div>
            </div>
          ) : mode === "authorShift" ? (
            <div className="mt-3 grid grid-cols-3 gap-3 font-mono text-[10.5px]">
              <div>
                <span className="text-neutral-600">{zh ? "前一窗口" : "Previous"}</span>
                <div className={`mt-1 text-[14px] font-bold ${selected.previousHighAuthorNet >= 0 ? "text-bull" : "text-bear"}`}>{signedInteger(selected.previousHighAuthorNet)}</div>
                <div className="mt-0.5 text-[8.5px] text-neutral-700">{selected.previousHighAuthorBullCount}/{selected.previousHighAuthorBearCount}</div>
              </div>
              <div>
                <span className="text-neutral-600">{zh ? "当前窗口" : "Current"}</span>
                <div className={`mt-1 text-[14px] font-bold ${selected.highAuthorNet >= 0 ? "text-bull" : "text-bear"}`}>{signedInteger(selected.highAuthorNet)}</div>
                <div className="mt-0.5 text-[8.5px] text-neutral-700">{selected.highAuthorBullCount}/{selected.highAuthorBearCount}</div>
              </div>
              <div>
                <span className="text-neutral-600">{zh ? "变化排名" : "Change rank"}</span>
                <div className="mt-1 text-[14px] font-bold text-[#8CBBFF]">#{selected.authorNetShiftRank}</div>
                <div className={`mt-0.5 text-[8.5px] ${selected.authorNetDelta >= 0 ? "text-bull" : "text-bear"}`}>Δ {signedInteger(selected.authorNetDelta)}</div>
              </div>
            </div>
          ) : (
            <>
              <div className="mt-3 flex h-2 overflow-hidden rounded-full bg-bear/80">
                <div className="h-full bg-bull" style={{ width: `${highRatio(selected)}%` }} />
              </div>
              <div className="mt-1.5 flex items-center justify-between font-mono text-[10.5px]">
                <span className="text-bull">{zh ? "看多" : "Bull"} {selected.highBullCalls}</span>
                <span className="text-bear">{zh ? "看空" : "Bear"} {selected.highBearCalls}</span>
              </div>
            </>
          )}
        </div>

        <div className="py-4">
          <div className="flex items-center justify-between gap-3 text-[9.5px]">
            <span className="font-semibold uppercase tracking-[0.1em] text-neutral-500">{mode === "newCoverage"
              ? (zh ? "覆盖基线" : "Coverage baseline")
              : mode === "authorShift" ? (zh ? "当前窗口作者人数" : "Current author headcount") : (zh ? "作者人数口径" : "Author headcount")}</span>
            <span className="text-neutral-700">{mode === "newCoverage"
              ? (zh ? `当前 ${windowKey} vs 此前 180 天` : `Current ${windowKey} vs prior 180D`)
              : mode === "authorShift" ? (zh ? "与前一等长窗口比较" : "Compared with prior equal window") : (zh ? "每位作者最新观点 · 不参与当前排序" : "Latest call per author · not ranked")}</span>
          </div>
          {mode === "newCoverage" ? (
            <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-3 text-[11px]">
              <div>
                <dt className="text-neutral-600">{zh ? "新增高 Score 作者" : "New high-Score voices"}</dt>
                <dd className="mt-1 font-mono text-[16px] font-bold text-[#8CBBFF]">{selected.newCoverageAuthorCount}</dd>
              </div>
              <div>
                <dt className="text-neutral-600">{zh ? "当前覆盖作者" : "Current voices"}</dt>
                <dd className="mt-1 font-mono text-[16px] font-bold text-cream">{selected.currentTopAuthorCount}</dd>
              </div>
              <div>
                <dt className="text-neutral-600">{zh ? "此前覆盖作者" : "Prior voices"}</dt>
                <dd className="mt-1 font-mono text-[16px] font-bold text-neutral-300">{selected.priorTopAuthorCount}</dd>
              </div>
              <div>
                <dt className="text-neutral-600">{zh ? "新增覆盖率" : "New-coverage ratio"}</dt>
                <dd className="mt-1 font-mono text-[16px] font-bold text-[#8CBBFF]">{selected.newCoverageRatio.toFixed(1)}%</dd>
              </div>
            </dl>
          ) : (
            <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-3 text-[11px]">
              <div>
                <dt className="text-neutral-600">{zh ? "看多作者" : "Bull authors"}</dt>
                <dd className="mt-1 font-mono text-[16px] font-bold text-bull">{selected.highAuthorBullCount}</dd>
              </div>
              <div>
                <dt className="text-neutral-600">{zh ? "看空作者" : "Bear authors"}</dt>
                <dd className="mt-1 font-mono text-[16px] font-bold text-bear">{selected.highAuthorBearCount}</dd>
              </div>
              <div>
                <dt className="text-neutral-600">{zh ? "作者净人数" : "Net authors"}</dt>
                <dd className={`mt-1 font-mono text-[16px] font-bold ${selected.highAuthorNet >= 0 ? "text-bull" : "text-bear"}`}>{signedInteger(selected.highAuthorNet)}</dd>
              </div>
              <div>
                <dt className="text-neutral-600">{zh ? "作者共识度" : "Author consensus"}</dt>
                <dd className={`mt-1 font-mono text-[16px] font-bold ${selected.highAuthorConsensus >= 0 ? "text-bull" : "text-bear"}`}>{selected.highAuthorConsensus > 0 ? "+" : ""}{selected.highAuthorConsensus.toFixed(1)}%</dd>
              </div>
              <div>
                <dt className="text-neutral-600">{zh ? "看多加权" : "Bull weight"}</dt>
                <dd className="mt-1 font-mono text-[16px] font-bold text-bull">{selected.highBullScore.toFixed(1)}</dd>
              </div>
              <div>
                <dt className="text-neutral-600">{zh ? "看空加权" : "Bear weight"}</dt>
                <dd className="mt-1 font-mono text-[16px] font-bold text-bear">{selected.highBearScore.toFixed(1)}</dd>
              </div>
            </dl>
          )}
        </div>

        <div className="border-t border-line pt-3">
          <div className="text-[10px] font-semibold uppercase tracking-[0.1em] text-neutral-500">{zh ? "为什么入榜" : "Why it ranks"}</div>
          <p className="mt-1.5 text-[10.5px] leading-[1.55] text-neutral-400">
            {mode === "newCoverage"
              ? (zh
                ? `当前 ${windowKey} 有 ${selected.newCoverageAuthorCount} 位平台 Top 10% Score 作者首次覆盖 ${selected.ticker}；这些作者在此前 180 天没有对该标的发布可执行观点。当前共有 ${selected.currentTopAuthorCount} 位高 Score 作者覆盖，新增占 ${selected.newCoverageRatio.toFixed(1)}%。`
                : `${selected.newCoverageAuthorCount} platform Top 10% Score voices covered ${selected.ticker} for the first time in the current ${windowKey}. They had no actionable call on it in the prior 180 days. New voices are ${selected.newCoverageRatio.toFixed(1)}% of the ${selected.currentTopAuthorCount} current high-Score voices.`)
              : mode === "contrast"
                ? (zh
                  ? `Top 10% 作者净方向 ${signed(selected.highNet)}，Bottom 10% 作者净方向 ${signed(selected.lowNet)}，两组方向相反。`
                  : `Top 10% net is ${signed(selected.highNet)} while Bottom 10% net is ${signed(selected.lowNet)}; the groups point in opposite directions.`)
                : mode === "authorShift"
                  ? (zh
                    ? `前一${windowKey}作者净人数 ${signedInteger(selected.previousHighAuthorNet)}，当前${windowKey}为 ${signedInteger(selected.highAuthorNet)}，净变化 ${signedInteger(selected.authorNetDelta)}；按两期较大作者规模归一化后，突变幅度为 ${metricText(selected, mode)}。`
                    : `Net authors moved from ${signedInteger(selected.previousHighAuthorNet)} in the prior ${windowKey} to ${signedInteger(selected.highAuthorNet)} now, a ${signedInteger(selected.authorNetDelta)} change and ${metricText(selected, mode)} normalized shift.`)
                  : (zh
                    ? `Top 10% 作者中有 ${selected.highBullCalls} 条看多、${selected.highBearCalls} 条看空；看多加权 ${selected.highBullScore.toFixed(1)}，看空加权 ${selected.highBearScore.toFixed(1)}，净方向 ${signed(selected.highNet)}。`
                    : `Top 10% voices made ${selected.highBullCalls} bull and ${selected.highBearCalls} bear calls. Bull weight is ${selected.highBullScore.toFixed(1)}, bear weight is ${selected.highBearScore.toFixed(1)}, for a ${signed(selected.highNet)} net.`)}
          </p>
          {mode === "newCoverage" ? (
            <p className="mt-2 border-l-2 border-[#6EA8FE]/30 pl-2 text-[10px] leading-[1.5] text-neutral-500">
              {selected.cohortNew
                ? (zh
                  ? `此前 180 天没有任何当前 Top 10% 作者覆盖 ${selected.ticker}，因此它属于高 Score 作者池中的全新标的。`
                  : `No current Top 10% voice covered ${selected.ticker} in the prior 180 days, so it is new to the high-Score cohort.`)
                : (zh
                  ? `此前 180 天已有 ${selected.priorTopAuthorCount} 位当前 Top 10% 作者覆盖 ${selected.ticker}；本次信号表示新的高 Score 作者开始加入关注。`
                  : `${selected.priorTopAuthorCount} current Top 10% voices already covered ${selected.ticker} in the prior 180 days; this signal marks additional high-Score voices joining.`)}
            </p>
          ) : mode === "authorShift" ? (
            <p className="mt-2 border-l-2 border-[#6EA8FE]/30 pl-2 text-[10px] leading-[1.5] text-neutral-500">
              {zh
                ? `突变判定：|净人数变化| ≥ 3、|突变幅度| ≥ 50%，且前后两个窗口都至少有 3 位作者。当前${selected.authorNetAbrupt ? "达到" : "未达到"}阈值。`
                : `Abrupt when |net change| ≥ 3, |shift| ≥ 50%, and both windows contain at least 3 authors. This ticker ${selected.authorNetAbrupt ? "meets" : "does not meet"} the threshold.`}
            </p>
          ) : mode !== "contrast" ? (
            <p className="mt-2 border-l-2 border-white/10 pl-2 text-[10px] leading-[1.5] text-neutral-500">
              {zh
                ? `按每位作者的最新观点去重后：${selected.highAuthorBullCount} 人看多、${selected.highAuthorBearCount} 人看空，作者净人数 ${signedInteger(selected.highAuthorNet)}，共识度 ${selected.highAuthorConsensus > 0 ? "+" : ""}${selected.highAuthorConsensus.toFixed(1)}%。`
                : `Using each author's latest call: ${selected.highAuthorBullCount} bull, ${selected.highAuthorBearCount} bear, net authors ${signedInteger(selected.highAuthorNet)}, consensus ${selected.highAuthorConsensus > 0 ? "+" : ""}${selected.highAuthorConsensus.toFixed(1)}%.`}
            </p>
          ) : null}
        </div>

        <div className="mt-4 border-t border-line pt-3">
          <div className="flex items-center justify-between gap-3">
            <div className="text-[10px] font-semibold uppercase tracking-[0.1em] text-neutral-500">
              {mode === "newCoverage"
                ? (zh ? "新增覆盖原始证据" : "New-coverage evidence")
                : mode === "contrast"
                  ? (zh ? "高 Score 证据" : "High-Score evidence")
                  : mode === "authorShift" ? (zh ? "当前窗口代表证据" : "Current-window evidence")
                    : mode === "bullish" ? (zh ? "代表性看多证据" : "Representative bull evidence") : (zh ? "代表性看空证据" : "Representative bear evidence")}
            </div>
            <span className="text-[9px] text-neutral-700">{zh ? "可打开原始来源" : "Traceable sources"}</span>
          </div>
          <div className="mt-1">
            {primaryEvidence.map((evidence) => <EvidenceItem key={evidence.id} evidence={evidence} zh={zh} />)}
            {(mode === "authorShift" || mode === "newCoverage") && !primaryEvidence.length ? <p className="py-3 text-[10px] text-neutral-600">{zh ? "当前窗口没有可展示的 Top 10% 作者观点。" : "No current-window Top 10% evidence."}</p> : null}
          </div>
        </div>

        {counterEvidence.length ? (
          <div className="mt-3 border-t border-line pt-3">
            <div className="text-[10px] font-semibold uppercase tracking-[0.1em] text-neutral-600">
              {mode === "newCoverage"
                ? (zh ? "反向首提证据" : "Opposite new-coverage evidence")
                : mode === "contrast"
                  ? (zh ? "低 Score 反向证据" : "Low-Score counter evidence")
                  : mode === "authorShift" ? (zh ? "前一窗口代表证据" : "Previous-window evidence") : (zh ? "反方证据" : "Counter evidence")}
            </div>
            <div className="mt-1">
              {counterEvidence.slice(0, 2).map((evidence) => <EvidenceItem key={evidence.id} evidence={evidence} zh={zh} />)}
            </div>
          </div>
        ) : null}

        <LocaleLink href={`/tickers/${selected.ticker}`} className="mt-4 flex h-9 shrink-0 items-center justify-center rounded-lg bg-reddit text-[12px] font-bold text-[#12201d] transition hover:brightness-110">
          {zh ? "查看标的详情" : "Open ticker"}
        </LocaleLink>
      </div>
    </aside>
  );
}
