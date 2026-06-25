"use client";

// KOL 个体观点模块容器：
//   ┌ 常驻：「股价与观点结合的折线 K 线图」(KolOpinionFlow) + 底部区间滑块 —— 拖手柄选一段时间区间
//   └ 下方：该区间观点的「分类区」(ClassifiedOpinions) —— 按 KOL / 视角 / 热度 三种方式组织
// range（起止日）+ vis（来源筛选）由本容器持有，图与分类区共享 → 选定区间与来源后，分类区只展示对应观点。
import { useMemo, useState } from "react";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { KolOpinionFlow } from "./KolOpinionFlow";
import { OpinionExplorer } from "./OpinionExplorer";
import type { KolFlow, KolOpinion, KolSource } from "@/lib/mockDetail";

export function KolModule({ flow, pool }: { flow: KolFlow; pool?: KolOpinion[] }) {
  const { lang } = useLocale();
  const zh = lang === "zh";
  const { days, opinions } = flow;

  // 折线图仍保留区间滑块 + 来源筛选（只作用于图本身）
  const fullRange = useMemo<[string, string]>(
    () => [days[0]?.day ?? "", days[days.length - 1]?.day ?? ""],
    [days]
  );
  const [range, setRange] = useState<[string, string]>(fullRange);
  const [vis, setVis] = useState<Record<KolSource, boolean>>({ x: true, youtube: true, reddit: true, xueqiu: true });
  const toggle = (s: KolSource) => setVis((v) => ({ ...v, [s]: !v[s] }));

  // 观点浏览器用近 ~30 天的扁平池（pool）；mock 标的无 pool 时回退图表的 opinions
  const explorerPool = pool && pool.length ? pool : opinions;

  return (
    <div>
      {/* 常驻图表：股价折线 + 观点气泡 + 区间滑块 */}
      <KolOpinionFlow days={days} opinions={opinions} range={range} onRangeChange={setRange} vis={vis} onToggle={toggle} />

      {/* 观点浏览器：筛选条（平台/立场/视角/时间/语言/相关性）+ 主从阅读（替代原 按KOL/按视角/按热度） */}
      <div className="mt-4 border-t border-line pt-4">
        <OpinionExplorer opinions={explorerPool} zh={zh} />
      </div>
    </div>
  );
}
