"use client";

// YouTube「完整口播」的阅读容器（标的页 OpinionExplorer 右侧阅读面板内）：
//   ① 顶部「投资者摘要」——AI 把整段口播的精华/话题提成分点（yt_digest.summary）。
//   ② 正文（YtFullContent）默认**折叠到约一屏**，点「展开更多」看全文。
//   ③ 正文右侧「内容目录」——口播按话题切的有序章节（yt_digest.chapters）；点标题→正文平滑滚到该段
//      （锚点 data-ch 由 YtFullContent 按 seg 埋）。跳转前自动展开，避免目标落在折叠区里。
import { useEffect, useRef, useState } from "react";
import type { YtSeg, YtDigest } from "@/lib/mockDetail";
import { YtFullContent } from "./YtFullContent";

export function YtReader({ segments, digest, zh, noCollapse }: { segments: YtSeg[]; digest?: YtDigest; zh: boolean; noCollapse?: boolean }) {
  const chapters = digest?.chapters ?? [];
  const summary = digest?.summary ?? [];
  const bodyRef = useRef<HTMLDivElement>(null);
  const [expanded, setExpanded] = useState(false);
  // 默认折叠（needsCollapse=true 起步，避免水合时先闪一下全文）；挂载后量一次：内容没超过约一屏就不折叠。
  // noCollapse=true（外层已有固定高度滚动容器，如观点浏览器右侧阅读面板）→ 不折叠，口播全量铺开、由外层滚动。
  const [needsCollapse, setNeedsCollapse] = useState(!noCollapse);

  useEffect(() => {
    if (noCollapse) { setNeedsCollapse(false); return; }
    const el = bodyRef.current;
    if (!el) return;
    const max = window.innerHeight * 0.72; // ≈ 一屏
    setNeedsCollapse(el.scrollHeight > max + 48);
  }, [segments, noCollapse]);

  const collapsed = needsCollapse && !expanded;

  const jump = (ci: number) => {
    setExpanded(true); // 先展开再滚（目标可能在折叠区里）
    setTimeout(() => {
      bodyRef.current?.querySelector<HTMLElement>(`[data-ch="${ci}"]`)
        ?.scrollIntoView({ behavior: "smooth", block: "start" });
    }, 60);
  };

  return (
    <div className="mt-3">
      {/* ① 投资者摘要 */}
      {summary.length > 0 && (
        <div className="mb-3 rounded-lg bg-elevated/50 p-3 ring-1 ring-inset ring-line">
          <div className="mb-2 flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide text-[#57D7BA]">
            <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
              <path d="M9 11l3 3L22 4M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11" />
            </svg>
            {zh ? "投资者摘要" : "Investor summary"}
          </div>
          <ul className="space-y-1.5">
            {summary.map((b, i) => (
              <li key={i} className="flex gap-2 text-[12.5px] leading-relaxed text-neutral-200">
                <span className="mt-[7px] h-1 w-1 shrink-0 rounded-full bg-[#57D7BA]" />
                <span>{zh ? b.zh : b.en}</span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* ②正文（折叠） + ③右侧目录（用 md: 断点——阅读面板在象限里仅约 950px 宽，lg 永不触发会把目录挤到上方） */}
      <div className="flex flex-col gap-4 md:flex-row md:gap-5">
        <div className="order-2 min-w-0 md:order-1 md:flex-1">
          <div className="relative">
            <div ref={bodyRef} className={collapsed ? "max-h-[72vh] overflow-hidden" : ""}>
              <YtFullContent segments={segments} chapters={chapters} zh={zh} />
            </div>
            {collapsed && (
              <div className="pointer-events-none absolute inset-x-0 bottom-0 h-28 bg-gradient-to-t from-card to-transparent" />
            )}
          </div>
          {needsCollapse && (
            <button
              onClick={() => setExpanded((e) => !e)}
              className="mt-2 flex items-center gap-1 rounded-md px-2.5 py-1 text-[12px] font-medium text-[#57D7BA] ring-1 ring-inset ring-line transition hover:bg-elevated"
            >
              {expanded ? (zh ? "收起" : "Collapse") : (zh ? "展开更多" : "Show more")}
              <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden
                   className={`transition-transform ${expanded ? "rotate-180" : ""}`}>
                <path d="M6 9l6 6 6-6" />
              </svg>
            </button>
          )}
        </div>

        {/* ③ 内容目录（点击跳转） */}
        {chapters.length > 0 && (
          <nav className="order-1 md:order-2 md:w-[188px] md:shrink-0">
            <div className="md:sticky md:top-3">
              <div className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-neutral-500">
                {zh ? "内容目录" : "Contents"}
              </div>
              <ol className="border-l border-line">
                {chapters.map((c, ci) => (
                  <li key={ci}>
                    <button
                      onClick={() => jump(ci)}
                      className="-ml-px block w-full border-l-2 border-transparent py-1 pl-3 text-left text-[12px] leading-snug text-neutral-400 transition hover:border-[#57D7BA] hover:text-cream"
                    >
                      {zh ? c.title.zh : c.title.en}
                    </button>
                  </li>
                ))}
              </ol>
            </div>
          </nav>
        )}
      </div>
    </div>
  );
}
