"use client";

// 个股页「高质量 DD 帖」模块：客户端切换排序（最近 / 质量 / 热度，默认最近）+ 加载更多。
// 卡片在服务端渲染后作为 children 传入，这里只对它们重新排序、按需显示，
// 因此不会把 FeedCard 及其依赖打进客户端包（静态导出友好）；「加载更多」是纯前端展开
// 已下载好的内容（构建期最多嵌入 48 篇），无需请求后端。
import { Children, useState } from "react";
import { SectionTitle } from "@/components/ui";

type SortKey = "recent" | "quality" | "score";
type Meta = { created: string; quality: number; score: number };

const PAGE = 12;

export function TickerDDPosts({
  title,
  hintPre,
  hintPost,
  labels,
  moreLabel,
  meta,
  children,
}: {
  title: string;
  hintPre: string;
  hintPost: string;
  labels: { recent: string; quality: string; score: string };
  moreLabel: string;
  meta: Meta[];
  children: React.ReactNode;
}) {
  const [sort, setSort] = useState<SortKey>("recent");
  const [visible, setVisible] = useState(PAGE);
  const cards = Children.toArray(children);

  // meta[i] 对应第 i 张卡片（children 与 meta 同序）。按所选规则排序全部索引，再按 visible 截取。
  const order = meta
    .map((_, i) => i)
    .sort((ia, ib) => {
      const a = meta[ia];
      const b = meta[ib];
      if (sort === "quality") return (b.quality || 0) - (a.quality || 0);
      if (sort === "score") return (b.score || 0) - (a.score || 0);
      return new Date(b.created).getTime() - new Date(a.created).getTime();
    });

  const opts: { key: SortKey; label: string }[] = [
    { key: "recent", label: labels.recent },
    { key: "quality", label: labels.quality },
    { key: "score", label: labels.score },
  ];

  return (
    <div>
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <SectionTitle title={title} hint={`${hintPre}${meta.length}${hintPost}`} accent="gold" icon="doc" />
        <div className="flex items-center gap-0.5 rounded-lg bg-white/[.03] ring-1 ring-inset ring-white/8 p-0.5 shrink-0">
          {opts.map((o) => (
            <button
              key={o.key}
              type="button"
              onClick={() => setSort(o.key)}
              aria-pressed={sort === o.key}
              className={`px-2.5 py-1 text-xs rounded-md transition ${
                sort === o.key
                  ? "bg-reddit/15 text-reddit font-medium"
                  : "text-neutral-500 hover:text-neutral-300"
              }`}
            >
              {o.label}
            </button>
          ))}
        </div>
      </div>
      {/* 全部卡片都渲染进静态页（保证"加载更多"有内容可揭示）；超出 visible 的用 CSS 隐藏。
          排序变化时按 order 重排，wrapper key 用原始索引保持卡片身份稳定。 */}
      <div className="grid md:grid-cols-2 gap-4 mt-4">
        {order.map((cardIdx, rank) => (
          <div key={cardIdx} className={rank < visible ? undefined : "hidden"}>
            {cards[cardIdx]}
          </div>
        ))}
      </div>
      {visible < order.length && (
        <div className="mt-5 flex justify-center">
          <button
            type="button"
            onClick={() => setVisible((v) => v + PAGE)}
            className="px-4 py-2 text-sm rounded-lg ring-1 ring-inset ring-white/10 bg-white/[.02] text-neutral-300 hover:text-cream hover:ring-white/20 transition"
          >
            {moreLabel}
          </button>
        </div>
      )}
    </div>
  );
}
