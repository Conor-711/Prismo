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
  const rootRef = useRef<HTMLDivElement>(null);
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

  const scrollWithinReader = (target: HTMLElement, extraOffset = 10) => {
    const scroller = rootRef.current?.closest<HTMLElement>("[data-reader-scroll]");
    if (!scroller) {
      target.scrollIntoView({ behavior: "smooth", block: "start" });
      return;
    }
    const scrollerRect = scroller.getBoundingClientRect();
    const targetRect = target.getBoundingClientRect();
    const top = scroller.scrollTop + targetRect.top - scrollerRect.top - extraOffset;
    scroller.scrollTo({ top: Math.max(0, top), behavior: "smooth" });
  };

  const jump = (ci: number) => {
    setExpanded(true); // 先展开再滚（目标可能在折叠区里）
    setTimeout(() => {
      const target = bodyRef.current?.querySelector<HTMLElement>(`[data-ch="${ci}"]`);
      if (target) scrollWithinReader(target, 14);
    }, 60);
  };

  const backToTop = () => {
    const scroller = rootRef.current?.closest<HTMLElement>("[data-reader-scroll]");
    if (scroller) {
      scroller.scrollTo({ top: 0, behavior: "smooth" });
      return;
    }
    if (rootRef.current) scrollWithinReader(rootRef.current, 0);
  };

  return (
    <div ref={rootRef} className="mt-3">
      {/* ① 投资者摘要 */}
      {summary.length > 0 && (
        <div className="mb-3 rounded-lg bg-elevated/50 p-3.5 ring-1 ring-inset ring-line">
          <div className="mb-2.5 flex items-center gap-1.5 text-[12.5px] font-semibold uppercase tracking-wide text-[#57D7BA]">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
              <path d="M9 11l3 3L22 4M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11" />
            </svg>
            {zh ? "投资者摘要" : "Investor summary"}
          </div>
          <ul className="space-y-2">
            {summary.map((b, i) => (
              <li key={i} className="flex gap-2.5 text-[14px] leading-relaxed text-neutral-100">
                <span className="mt-[7px] h-1 w-1 shrink-0 rounded-full bg-[#57D7BA]" />
                <span>{zh ? b.zh : b.en}</span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* ②正文（折叠） + ③浮动目录。目录 sticky 跟随右侧阅读面板滚动，且不挤压正文宽度。 */}
      <div className="relative">
        {/* ③ 内容目录（点击跳转） */}
        {chapters.length > 0 && (
          <div className="sticky top-2 z-20 -mb-8 flex h-8 justify-end pointer-events-none">
            <div className="group relative pointer-events-auto">
              <button
                type="button"
                className="inline-flex items-center gap-1.5 rounded-md border border-[#57D7BA]/70 bg-card/90 px-2.5 py-1.5 text-[12px] font-semibold text-neutral-300 shadow-[0_0_18px_rgb(87_215_186_/_0.12)] ring-1 ring-inset ring-[#57D7BA]/35 backdrop-blur transition hover:border-[#57D7BA] hover:text-cream"
              >
                <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                  <path d="M4 6h16M4 12h16M4 18h16" />
                </svg>
                {zh ? "内容目录" : "Contents"}
              </button>
              <nav className="pointer-events-none absolute right-0 top-8 hidden w-[230px] rounded-lg bg-card/95 p-3 opacity-0 shadow-2xl ring-1 ring-inset ring-line backdrop-blur transition group-hover:pointer-events-auto group-hover:block group-hover:opacity-100 group-focus-within:pointer-events-auto group-focus-within:block group-focus-within:opacity-100">
                <div className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-neutral-500">
                  {zh ? "内容目录" : "Contents"}
                </div>
                <ol className="max-h-[320px] overflow-y-auto border-l border-line">
                  {chapters.map((c, ci) => (
                    <li key={ci}>
                      <button
                        onClick={() => jump(ci)}
                        className="-ml-px block w-full border-l-2 border-transparent py-1.5 pl-3 text-left text-[12px] leading-snug text-neutral-400 transition hover:border-[#57D7BA] hover:text-cream"
                      >
                        {zh ? c.title.zh : c.title.en}
                      </button>
                    </li>
                  ))}
                </ol>
              </nav>
            </div>
          </div>
        )}

        <div className="min-w-0">
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
          <div className="sticky bottom-3 z-20 -mt-9 flex justify-end pointer-events-none">
            <button
              type="button"
              onClick={backToTop}
              className="pointer-events-auto inline-flex items-center gap-1 rounded-md border border-[#57D7BA]/55 bg-card/90 px-2.5 py-1.5 text-[12px] font-semibold text-[#57D7BA] shadow-lg backdrop-blur transition hover:border-[#57D7BA] hover:bg-elevated hover:text-cream"
            >
              <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
                <path d="M6 15l6-6 6 6" />
              </svg>
              {zh ? "顶部" : "Top"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
