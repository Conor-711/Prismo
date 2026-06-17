"use client";

import { useState } from "react";
import { FeedCard } from "./FeedCard";
import { useLocale } from "./i18n/LocaleProvider";
import type { FeedRow } from "@/lib/queries";

// 高质量 DD 帖网格：默认只显示前 initial 条，点「展开更多」客户端展开全部（无需翻页/重建）。
// 收起时回到前 initial 条。剩余数量显示在按钮上，让用户知道还有多少。
export function FeedGrid({
  posts,
  tickerBase = "/ticker",
  initial = 6,
}: {
  posts: FeedRow[];
  tickerBase?: string;
  initial?: number;
}) {
  const { dict } = useLocale();
  const t = dict.dashboard;
  const [expanded, setExpanded] = useState(false);
  const shown = expanded ? posts : posts.slice(0, initial);
  const remaining = posts.length - initial;

  return (
    <>
      <div className="grid md:grid-cols-2 gap-4">
        {shown.map((p) => (
          <FeedCard key={p.id} p={p} tickerBase={tickerBase} />
        ))}
      </div>
      {remaining > 0 && (
        <div className="mt-5 flex justify-center">
          <button
            type="button"
            onClick={() => setExpanded((v) => !v)}
            aria-expanded={expanded}
            className="inline-flex items-center gap-2 rounded-full px-5 py-2.5 text-sm font-semibold text-cream ring-1 ring-inset ring-line bg-white/[.02] hover:bg-white/[.05] hover:ring-white/20 transition"
          >
            {expanded ? t.ddLess : `${t.ddMore} · ${remaining}`}
            <svg
              viewBox="0 0 16 16"
              className={`w-3.5 h-3.5 transition-transform ${expanded ? "rotate-180" : ""}`}
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              aria-hidden
            >
              <path d="M4 6l4 4 4-4" />
            </svg>
          </button>
        </div>
      )}
    </>
  );
}
