"use client";

import { useMemo } from "react";
import { Panel } from "@/components/ui";
import { SV_HORIZONS, type SvBoard, type SvDistribution, type SvHorizon, type SvInvestor } from "@/features/smart-voice/svMock";

const TYPE_LABEL: Record<string, { zh: string; en: string }> = {
  technical: { zh: "技术分析", en: "Technical" },
  fundamental: { zh: "基本面", en: "Fundamental" },
  event_driven: { zh: "事件驱动", en: "Event driven" },
  macro: { zh: "宏观", en: "Macro" },
  flow_momentum: { zh: "资金流 / 动量", en: "Flow / momentum" },
  mixed: { zh: "混合", en: "Mixed" },
  unknown: { zh: "未分类", en: "Unknown" },
};

function typeLabel(type: string | undefined, zh: boolean) {
  const key = type || "unknown";
  return TYPE_LABEL[key]?.[zh ? "zh" : "en"] ?? key;
}

function scoreTone(score: number) {
  if (score >= 130) return "text-bull";
  if (score >= 115) return "text-reddit";
  if (score >= 95) return "text-cream";
  if (score >= 80) return "text-amber";
  return "text-bear";
}

function confidenceLabel(confidence: SvInvestor["confidence"], zh: boolean) {
  if (confidence === "high") return zh ? "高置信" : "High";
  if (confidence === "medium") return zh ? "中置信" : "Medium";
  if (confidence === "low") return zh ? "低置信" : "Low";
  return zh ? "观察中" : "Observing";
}

function dominantType(inv: SvInvestor) {
  return inv.concentration?.dominantInvestorType || "unknown";
}

function averageHorizon(inv: SvInvestor, keys: SvHorizon[]) {
  const vals = keys
    .map((key) => inv.horizonScores[key])
    .filter((value): value is number => typeof value === "number");
  if (!vals.length) return -Infinity;
  return vals.reduce((sum, value) => sum + value, 0) / vals.length;
}

function horizonSpread(inv: SvInvestor) {
  const vals = SV_HORIZONS.map((key) => inv.horizonScores[key]).filter((value): value is number => typeof value === "number");
  if (!vals.length) return 0;
  return Math.max(...vals) - Math.min(...vals);
}

function fallbackDistribution(investors: SvInvestor[]): SvDistribution {
  const scores = investors.map((inv) => inv.sv).sort((a, b) => a - b);
  const quantile = (q: number) => {
    if (!scores.length) return 0;
    const pos = (scores.length - 1) * q;
    const lo = Math.floor(pos);
    const hi = Math.ceil(pos);
    if (lo === hi) return scores[lo];
    return scores[lo] * (hi - pos) + scores[hi] * (pos - lo);
  };
  const min = Math.floor((scores[0] || 0) / 5) * 5;
  const max = Math.ceil((scores[scores.length - 1] || 100) / 5) * 5;
  const count = 24;
  const bins = Array.from({ length: count }, (_, i) => ({ from: min + ((max - min) / count) * i, to: min + ((max - min) / count) * (i + 1), count: 0 }));
  for (const score of scores) {
    const idx = Math.min(count - 1, Math.max(0, Math.floor(((score - min) / Math.max(1, max - min)) * count)));
    bins[idx].count += 1;
  }
  return {
    count: scores.length,
    min: scores[0] || 0,
    q25: Math.round(quantile(0.25)),
    median: Math.round(quantile(0.5)),
    q75: Math.round(quantile(0.75)),
    max: scores[scores.length - 1] || 0,
    top10Threshold: investors[9]?.sv || 0,
    bottom10Threshold: investors[investors.length - 10]?.sv || 0,
    bins,
  };
}

function InvestorMini({ inv, zh, metric }: { inv: SvInvestor; zh: boolean; metric?: string }) {
  const delta = typeof inv.svDelta === "number" && inv.svDelta !== 0 ? inv.svDelta : null;
  const rankDelta = typeof inv.rankDelta === "number" && inv.rankDelta !== 0 ? inv.rankDelta : null;
  return (
    <div className="flex min-w-0 items-center gap-2.5 border-b border-line/70 px-3 py-2.5 last:border-b-0">
      <div className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-white/[.05] text-[12px] font-bold text-reddit ring-1 ring-inset ring-white/10">
        {(inv.name || inv.handle || "?").replace(/^@/, "").slice(0, 1).toUpperCase()}
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex min-w-0 items-center gap-2">
          <a href={inv.url} target="_blank" rel="noreferrer noopener" className="truncate text-[13px] font-semibold text-cream hover:text-reddit">
            @{inv.handle}
          </a>
          {inv.rank ? <span className="shrink-0 font-mono text-[10px] text-neutral-600">#{inv.rank}</span> : null}
        </div>
        <div className="mt-0.5 flex flex-wrap items-center gap-1.5 text-[10.5px] text-neutral-500">
          <span>{typeLabel(dominantType(inv), zh)}</span>
          <span>·</span>
          <span>{confidenceLabel(inv.confidence, zh)}</span>
          {rankDelta ? (
            <>
              <span>·</span>
              <span className={rankDelta > 0 ? "text-bull" : "text-bear"}>{rankDelta > 0 ? "↑" : "↓"}{Math.abs(rankDelta)}</span>
            </>
          ) : null}
          {metric ? (
            <>
              <span>·</span>
              <span>{metric}</span>
            </>
          ) : null}
        </div>
      </div>
      <div className="text-right">
        <div className={`font-display text-[20px] font-extrabold tabular ${scoreTone(inv.sv)}`}>{inv.sv}</div>
        {delta ? <div className={`font-mono text-[10px] ${delta > 0 ? "text-bull" : "text-bear"}`}>{delta > 0 ? "+" : ""}{delta}</div> : null}
      </div>
    </div>
  );
}

export function StatCell({ label, value, tone = "text-cream" }: { label: string; value: string; tone?: string }) {
  return (
    <div className="min-w-0 rounded-lg bg-white/[.025] px-3 py-2 ring-1 ring-inset ring-white/[.06]">
      <div className="truncate text-[10px] uppercase tracking-[0.12em] text-neutral-600">{label}</div>
      <div className={`mt-1 font-mono text-[15px] font-bold leading-none tabular ${tone}`}>{value}</div>
    </div>
  );
}

export function DistributionPanel({ board, zh }: { board: SvBoard; zh: boolean }) {
  const distribution = board.distribution ?? fallbackDistribution(board.investors);
  const maxCount = Math.max(1, ...distribution.bins.map((bin) => bin.count));
  const range = Math.max(1, distribution.max - distribution.min);
  const marker = (score: number) => `${Math.max(0, Math.min(100, ((score - distribution.min) / range) * 100))}%`;

  return (
    <Panel className="flex min-h-0 flex-col overflow-hidden">
      <div className="flex items-start justify-between gap-3 border-b border-line px-4 py-3">
        <div>
          <div className="text-[10px] font-bold uppercase tracking-[0.16em] text-reddit">Market Distribution</div>
          <h2 className="mt-1 font-display text-[17px] font-extrabold text-cream">{zh ? "市场 SV 分布" : "Market SV distribution"}</h2>
        </div>
        <div className="text-right text-[11px] text-neutral-500">
          <div>{board.scoringVersion ?? "SV"}</div>
          <div>{board.updatedAt}</div>
        </div>
      </div>
      <div className="grid grid-cols-5 gap-2 px-4 py-3">
        <StatCell label={zh ? "全量作者" : "Investors"} value={`${board.totalInvestors ?? distribution.count}`} tone="text-reddit" />
        <StatCell label="Median" value={`${distribution.median}`} />
        <StatCell label="IQR" value={`${distribution.q25}-${distribution.q75}`} />
        <StatCell label="Top 10%" value={`${distribution.top10Threshold}`} tone="text-bull" />
        <StatCell label="Bottom 10%" value={`${distribution.bottom10Threshold}`} tone="text-bear" />
      </div>
      <div className="min-h-0 flex-1 px-4 pb-4">
        <div className="relative flex h-full min-h-[170px] items-end gap-1.5 border-b border-line/80 px-1 pb-7 pt-4 xl:min-h-[210px]">
          {distribution.bins.map((bin, index) => (
            <div key={`${bin.from}:${bin.to}:${index}`} className="flex min-w-0 flex-1 items-end">
              <div
                className="w-full rounded-t-sm bg-reddit/45 ring-1 ring-inset ring-reddit/15"
                style={{ height: `${Math.max(5, (bin.count / maxCount) * 100)}%` }}
                title={`${bin.from}-${bin.to}: ${bin.count}`}
              />
            </div>
          ))}
          <div className="absolute bottom-7 top-3 w-px bg-reddit" style={{ left: marker(distribution.median) }} />
          <div className="absolute bottom-7 top-3 w-px bg-bull/80" style={{ left: marker(distribution.top10Threshold) }} />
          <div className="absolute bottom-7 top-3 w-px bg-bear/80" style={{ left: marker(distribution.bottom10Threshold) }} />
          <div className="absolute bottom-1 left-0 right-0 flex justify-between px-1 font-mono text-[10px] text-neutral-600">
            <span>{distribution.min}</span>
            <span className="text-reddit">M {distribution.median}</span>
            <span>{distribution.max}</span>
          </div>
        </div>
      </div>
    </Panel>
  );
}

export function AlertsPanel({ board, zh }: { board: SvBoard; zh: boolean }) {
  const alerts = useMemo(() => {
    const all = new Map<string, SvInvestor>();
    for (const inv of board.investors) all.set(inv.id, inv);
    for (const inv of board.bottomInvestors ?? []) all.set(inv.id, inv);
    const withDelta = [...all.values()].filter((inv) => typeof inv.svDelta === "number" || typeof inv.rankDelta === "number");
    if (withDelta.length) {
      const svUp = [...withDelta].sort((a, b) => (b.svDelta ?? -Infinity) - (a.svDelta ?? -Infinity))[0];
      const svDown = [...withDelta].sort((a, b) => (a.svDelta ?? Infinity) - (b.svDelta ?? Infinity))[0];
      const rankUp = [...withDelta].sort((a, b) => (b.rankDelta ?? -Infinity) - (a.rankDelta ?? -Infinity))[0];
      const rankDown = [...withDelta].sort((a, b) => (a.rankDelta ?? Infinity) - (b.rankDelta ?? Infinity))[0];
      return [
        svUp && typeof svUp.svDelta === "number" && svUp.svDelta > 0 && {
          tone: "text-bull",
          title: zh ? "SV 上升最快" : "Fastest SV riser",
          body: zh ? `@${svUp.handle} SV ${svUp.sv}，较上次 +${svUp.svDelta}。` : `@${svUp.handle} is at SV ${svUp.sv}, up +${svUp.svDelta}.`,
        },
        svDown && typeof svDown.svDelta === "number" && svDown.svDelta < 0 && {
          tone: "text-bear",
          title: zh ? "SV 下滑最快" : "Fastest SV drop",
          body: zh ? `@${svDown.handle} SV ${svDown.sv}，较上次 ${svDown.svDelta}。` : `@${svDown.handle} is at SV ${svDown.sv}, down ${svDown.svDelta}.`,
        },
        rankUp && typeof rankUp.rankDelta === "number" && rankUp.rankDelta > 0 && {
          tone: "text-reddit",
          title: zh ? "排名上升最多" : "Biggest rank gain",
          body: zh ? `@${rankUp.handle} 当前排名 #${rankUp.rank}，上升 ${rankUp.rankDelta} 位。` : `@${rankUp.handle} is now #${rankUp.rank}, up ${rankUp.rankDelta} ranks.`,
        },
        rankDown && typeof rankDown.rankDelta === "number" && rankDown.rankDelta < 0 && {
          tone: "text-amber",
          title: zh ? "排名下降最多" : "Biggest rank drop",
          body: zh ? `@${rankDown.handle} 当前排名 #${rankDown.rank}，下降 ${Math.abs(rankDown.rankDelta)} 位。` : `@${rankDown.handle} is now #${rankDown.rank}, down ${Math.abs(rankDown.rankDelta)} ranks.`,
        },
      ].filter(Boolean) as { tone: string; title: string; body: string }[];
    }

    const top = board.investors[0];
    const highDispersion = [...board.investors].sort((a, b) => horizonSpread(b) - horizonSpread(a))[0];
    const weakHighConfidence = [...(board.bottomInvestors ?? [])].filter((inv) => inv.confidence === "high").sort((a, b) => a.sv - b.sv)[0];
    const short = [...board.investors].sort((a, b) => averageHorizon(b, ["1D", "5D"]) - averageHorizon(a, ["1D", "5D"]))[0];
    const long = [...board.investors].sort((a, b) => averageHorizon(b, ["60D", "90D", "180D"]) - averageHorizon(a, ["60D", "90D", "180D"]))[0];
    return [
      top && {
        tone: "text-bull",
        title: zh ? "最高 SV 继续集中" : "Highest SV concentration",
        body: zh ? `@${top.handle} 当前 SV ${top.sv}，排名 #${top.rank ?? 1}。` : `@${top.handle} is at SV ${top.sv}, rank #${top.rank ?? 1}.`,
      },
      highDispersion && {
        tone: "text-amber",
        title: zh ? "时间窗口分化显著" : "Horizon dispersion",
        body: zh
          ? `@${highDispersion.handle} 的窗口差 ${horizonSpread(highDispersion)}，应按优势周期使用。`
          : `@${highDispersion.handle} has a ${horizonSpread(highDispersion)}-point horizon spread; use by best horizon.`,
      },
      weakHighConfidence && {
        tone: "text-bear",
        title: zh ? "高置信低分风险" : "High-confidence low score",
        body: zh
          ? `@${weakHighConfidence.handle} 样本充分但 SV ${weakHighConfidence.sv}，需要关注系统性负贡献。`
          : `@${weakHighConfidence.handle} has enough evidence but only SV ${weakHighConfidence.sv}.`,
      },
      short && {
        tone: "text-reddit",
        title: zh ? "短线信号代表" : "Short-term specialist",
        body: zh
          ? `@${short.handle} 的 1D/5D 均值约 ${Math.round(averageHorizon(short, ["1D", "5D"]))}。`
          : `@${short.handle}'s 1D/5D average is about ${Math.round(averageHorizon(short, ["1D", "5D"]))}.`,
      },
      long && {
        tone: "text-reddit",
        title: zh ? "中长期信号代表" : "Medium/long-term specialist",
        body: zh
          ? `@${long.handle} 的 60D/90D/180D 均值约 ${Math.round(averageHorizon(long, ["60D", "90D", "180D"]))}。`
          : `@${long.handle}'s 60D/90D/180D average is about ${Math.round(averageHorizon(long, ["60D", "90D", "180D"]))}.`,
      },
    ].filter(Boolean) as { tone: string; title: string; body: string }[];
  }, [board, zh]);
  const hasDelta = useMemo(() => {
    const all = [...board.investors, ...(board.bottomInvestors ?? [])];
    return all.some((inv) => typeof inv.svDelta === "number" || typeof inv.rankDelta === "number");
  }, [board]);

  return (
    <Panel className="overflow-hidden">
      <div className="border-b border-line px-4 py-3">
        <div className="text-[10px] font-bold uppercase tracking-[0.16em] text-reddit">SV Alert</div>
        <h2 className="mt-1 font-display text-[17px] font-extrabold text-cream">{zh ? "Smart Voice 警报" : "Smart Voice alerts"}</h2>
      </div>
      <div className="divide-y divide-line/70">
        {alerts.map((alert) => (
          <div key={alert.title} className="grid grid-cols-[8px_minmax(0,1fr)] gap-3 px-4 py-3">
            <span className={`mt-1.5 h-2 w-2 rounded-full bg-current ${alert.tone}`} />
            <div className="min-w-0">
              <div className={`text-[13px] font-bold ${alert.tone}`}>{alert.title}</div>
              <p className="mt-1 text-[12px] leading-relaxed text-neutral-500">{alert.body}</p>
            </div>
          </div>
        ))}
      </div>
      <div className="border-t border-line px-4 py-2 text-[11px] text-neutral-600">
        {hasDelta
          ? (zh ? "已接入历史快照：警报基于最近两次 SV 导出之间的真实变化。" : "Historical snapshots connected: alerts use real changes between the latest two SV exports.")
          : (zh ? "注：首次快照暂无 delta；再次运行 export 后会显示真实 SV 变动。" : "Note: no delta on the first snapshot; run export again after the next score to show true SV changes.")}
      </div>
    </Panel>
  );
}

export function TypePanel({ board, zh }: { board: SvBoard; zh: boolean }) {
  const groups = useMemo(() => {
    const map = new Map<string, { count: number; total: number; top: SvInvestor | null }>();
    for (const inv of board.investors) {
      const key = dominantType(inv);
      const current = map.get(key) ?? { count: 0, total: 0, top: null };
      current.count += 1;
      current.total += inv.sv;
      if (!current.top || inv.sv > current.top.sv) current.top = inv;
      map.set(key, current);
    }
    return [...map.entries()].map(([key, value]) => ({ key, ...value, avg: value.total / value.count })).sort((a, b) => b.avg - a.avg);
  }, [board.investors]);
  const maxCount = Math.max(1, ...groups.map((g) => g.count));

  return (
    <Panel className="flex min-h-0 flex-col overflow-hidden">
      <div className="border-b border-line px-4 py-3">
        <div className="text-[10px] font-bold uppercase tracking-[0.16em] text-reddit">Investor Types</div>
        <h2 className="mt-1 font-display text-[17px] font-extrabold text-cream">{zh ? "投资者类型分布" : "Investor type distribution"}</h2>
      </div>
      <div className="min-h-0 flex-1 space-y-3 overflow-y-auto p-4">
        {groups.slice(0, 6).map((group) => (
          <div key={group.key}>
            <div className="mb-1 flex items-center justify-between gap-2 text-[12px]">
              <span className="font-semibold text-cream">{typeLabel(group.key, zh)}</span>
              <span className="font-mono text-neutral-500">{group.count} · avg {Math.round(group.avg)}</span>
            </div>
            <div className="h-2 overflow-hidden rounded-full bg-white/[.05]">
              <div className="h-full rounded-full bg-reddit" style={{ width: `${Math.max(6, (group.count / maxCount) * 100)}%` }} />
            </div>
            {group.top ? <div className="mt-1 text-[11px] text-neutral-600">{zh ? "代表：" : "Lead: "}@{group.top.handle}</div> : null}
          </div>
        ))}
      </div>
    </Panel>
  );
}

export function RankingPanel({ board, zh }: { board: SvBoard; zh: boolean }) {
  const top = board.investors.slice(0, 8);
  const bottom = (board.bottomInvestors ?? []).slice(-8);
  return (
    <Panel className="flex min-h-0 flex-col overflow-hidden">
      <div className="border-b border-line px-4 py-3">
        <div className="text-[10px] font-bold uppercase tracking-[0.16em] text-reddit">Rank Monitor</div>
        <h2 className="mt-1 font-display text-[17px] font-extrabold text-cream">{zh ? "SV 排名监控" : "SV rank monitor"}</h2>
      </div>
      <div className="grid min-h-0 flex-1 grid-cols-2 divide-x divide-line">
        <div className="min-w-0 overflow-y-auto">
          <div className="sticky top-0 z-10 border-b border-line bg-panel/95 px-3 py-2 text-[12px] font-bold text-bull">{zh ? "Top SV" : "Top SV"}</div>
          {top.map((inv) => <InvestorMini key={inv.id} inv={inv} zh={zh} />)}
        </div>
        <div className="min-w-0 overflow-y-auto">
          <div className="sticky top-0 z-10 border-b border-line bg-panel/95 px-3 py-2 text-[12px] font-bold text-bear">{zh ? "低 SV 观察" : "Low SV watch"}</div>
          {bottom.map((inv) => <InvestorMini key={inv.id} inv={inv} zh={zh} />)}
        </div>
      </div>
    </Panel>
  );
}

export function TypicalPanel({ board, zh }: { board: SvBoard; zh: boolean }) {
  const cases = useMemo(() => {
    const best = board.investors[0];
    const weakHigh = [...(board.bottomInvestors ?? [])].filter((inv) => inv.confidence === "high").sort((a, b) => a.sv - b.sv)[0];
    const short = [...board.investors].sort((a, b) => averageHorizon(b, ["1D", "5D"]) - averageHorizon(a, ["1D", "5D"]))[0];
    const long = [...board.investors].sort((a, b) => averageHorizon(b, ["60D", "90D", "180D"]) - averageHorizon(a, ["60D", "90D", "180D"]))[0];
    const split = [...board.investors].sort((a, b) => horizonSpread(b) - horizonSpread(a))[0];
    const rows: [string, SvInvestor | undefined, string][] = [
      [zh ? "最佳整体" : "Best overall", best, zh ? "总 SV 排名第一" : "Highest global SV"],
      [zh ? "高置信尾部" : "High-confidence tail", weakHigh, zh ? "样本充分但总分偏低" : "Enough evidence but weak score"],
      [zh ? "短线代表" : "Short-term", short, zh ? "1D/5D 表现最高" : "Highest 1D/5D profile"],
      [zh ? "长期代表" : "Long-term", long, zh ? "60D/90D/180D 表现最高" : "Highest 60D/90D/180D profile"],
      [zh ? "风格分化" : "Style split", split, zh ? "时间窗口差异最大" : "Largest horizon spread"],
    ];
    return rows.filter((row): row is [string, SvInvestor, string] => Boolean(row[1]));
  }, [board, zh]);

  return (
    <Panel className="flex min-h-0 flex-col overflow-hidden">
      <div className="border-b border-line px-4 py-3">
        <div className="text-[10px] font-bold uppercase tracking-[0.16em] text-reddit">Typical Cases</div>
        <h2 className="mt-1 font-display text-[17px] font-extrabold text-cream">{zh ? "典型投资者" : "Typical investors"}</h2>
      </div>
      <div className="min-h-0 flex-1 divide-y divide-line/70 overflow-y-auto">
        {cases.map(([label, inv, why]) => (
          <div key={label} className="grid grid-cols-[88px_minmax(0,1fr)] items-center gap-2 px-4 py-2.5 xl:grid-cols-[94px_minmax(0,1fr)]">
            <div className="text-[11px] font-bold text-neutral-500">{label}</div>
            <InvestorMini inv={inv} zh={zh} metric={why} />
          </div>
        ))}
      </div>
    </Panel>
  );
}
