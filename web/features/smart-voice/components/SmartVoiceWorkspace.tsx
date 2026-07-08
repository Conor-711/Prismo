"use client";

import { useLocale } from "@/components/i18n/LocaleProvider";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import type { SvBoard } from "@/features/smart-voice/svMock";
import {
  AlertsPanel,
  DistributionPanel,
  RankingPanel,
  StatCell,
  TypePanel,
  TypicalPanel,
} from "./SmartVoiceWorkspacePanels";

export function SmartVoiceWorkspace({ board }: { board: SvBoard }) {
  const { lang } = useLocale();
  const zh = lang === "zh";
  const top = board.investors[0];
  const total = board.totalInvestors ?? board.investors.length;
  const exported = board.exportedInvestors ?? board.investors.length;

  return (
    <div className="flex h-[calc(100vh-2rem)] min-h-[760px] flex-col overflow-hidden">
      <header className="mb-3 flex shrink-0 items-end justify-between gap-4 border-b border-line pb-3">
        <div className="min-w-0">
          <div className="text-[11px] font-bold uppercase tracking-[0.18em] text-reddit">Prismo · Smart Voice</div>
          <h1 className="mt-1 font-display text-[26px] font-extrabold leading-none text-cream">
            {zh ? "Smart Voice 工作台" : "Smart Voice Workbench"}
          </h1>
          <p className="mt-2 max-w-3xl text-[13px] text-neutral-500">
            {zh
              ? "追踪高质量投资者的能力分布、风格边界与当前异常信号。历史变动快照接入后，这里会直接显示 SV delta 与排名 delta。"
              : "Track high-quality investor distribution, style boundaries and current alert states. Historical snapshots will add true SV and rank deltas."}
          </p>
        </div>
        <div className="grid shrink-0 grid-cols-4 gap-2">
          <StatCell label={zh ? "全量" : "Total"} value={`${total}`} tone="text-reddit" />
          <StatCell label={zh ? "导出" : "Exported"} value={`${exported}`} />
          <StatCell label={zh ? "版本" : "Version"} value={board.scoringVersion ?? "SV"} />
          <StatCell label={zh ? "第一" : "Leader"} value={top ? `${top.sv}` : "—"} tone="text-bull" />
        </div>
      </header>

      <div className="grid min-h-0 flex-1 gap-3 lg:grid-cols-[420px_minmax(0,1fr)]">
        <div className="grid min-h-0 grid-rows-[auto_minmax(0,1fr)] gap-3">
          <AlertsPanel board={board} zh={zh} />
          <RankingPanel board={board} zh={zh} />
        </div>
        <div className="grid min-h-0 grid-rows-[minmax(0,1.2fr)_minmax(0,.8fr)] gap-3">
          <DistributionPanel board={board} zh={zh} />
          <div className="grid min-h-0 gap-3 lg:grid-cols-[380px_minmax(0,1fr)]">
            <TypePanel board={board} zh={zh} />
            <TypicalPanel board={board} zh={zh} />
          </div>
        </div>
      </div>

      <div className="mt-2 shrink-0 text-[11px] text-neutral-700">
        {zh ? "快照已接入；首次快照暂无 delta，下一次新版算法导出后会自动显示 SV 与排名变化。" : "Snapshots are connected; the first snapshot has no delta, and the next algorithm export will show SV and rank changes automatically."}
        <LocaleLink href="/investors" className="ml-2 text-reddit hover:text-cream">
          {zh ? "查看作者榜" : "Open authors"}
        </LocaleLink>
      </div>
    </div>
  );
}
