"use client";

// YouTube「完整口播」的阅读容器（标的页 OpinionExplorer 右侧阅读面板内）：
//   ① 顶部「投资者摘要」——AI 把整段口播的精华/话题提成分点（yt_digest.summary）。
//   ② 正文（YtFullContent）默认**折叠到约一屏**，点「展开更多」看全文。
//   ③ 正文右侧「内容目录」——口播按话题切的有序章节（yt_digest.chapters）；点标题→正文平滑滚到该段
//      （锚点 data-ch 由 YtFullContent 按 seg 埋）。跳转前自动展开，避免目标落在折叠区里。
import { useEffect, useRef, useState } from "react";
import type { KolJudgment, YtSeg, YtDigest } from "@/lib/mockDetail";
import { YtFullContent } from "./YtFullContent";

type Speech = { type: "speech"; text: string; speaker?: string };
type ReaderMode = "summary" | "raw";

const speechSegments = (segments: YtSeg[]): Speech[] =>
  (segments || []).filter((s): s is Speech => s.type === "speech" && Boolean(s.text?.trim()));

const splitParas = (text: string): string[] =>
  text
    .replace(/\r/g, "")
    .split(/\n{2,}/)
    .map((p) => p.replace(/[ \t]+/g, " ").trim())
    .filter(Boolean);

function readableInline(text: string) {
  const out: React.ReactNode[] = [];
  const re = /\*\*([^*]+?)\*\*|\*([^*\n]+?)\*|(\$?[A-Z]{1,6}\b)|(\$?\d[\d,.]*(?:\.\d+)?%?)/g;
  let last = 0;
  let k = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) out.push(text.slice(last, m.index));
    if (m[1] != null) {
      out.push(<strong key={k++} className="font-semibold text-cream">{m[1]}</strong>);
    } else if (m[2] != null) {
      out.push(<span key={k++} className="font-medium text-neutral-100">{m[2]}</span>);
    } else if (m[3] != null) {
      out.push(<span key={k++} className="font-mono text-[0.94em] font-semibold text-[#57D7BA]">{m[3]}</span>);
    } else if (m[4] != null) {
      out.push(<span key={k++} className="font-mono text-[0.94em] font-semibold text-cream">{m[4]}</span>);
    }
    last = re.lastIndex;
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}

const BUCKET_LABEL: Record<"short" | "mid" | "long", { zh: string; en: string }> = {
  short: { zh: "短线", en: "Short" },
  mid: { zh: "中线", en: "Mid" },
  long: { zh: "长线", en: "Long" },
};
const fmtPrice = (n: number) => (n >= 10 ? Math.round(n).toLocaleString() : String(+n.toFixed(2)));
const fmtRange = (lo?: number, hi?: number) => {
  if (lo == null) return "";
  const h = hi ?? lo;
  return h > lo ? `$${fmtPrice(lo)}–$${fmtPrice(h)}` : `$${fmtPrice(lo)}`;
};
const plainText = (text: string): string =>
  splitParas(text).join(" ").replace(/\*\*/g, "").replace(/\*/g, "").replace(/\s+/g, " ").trim();
const excerpt = (text: string, max = 138): string => {
  const t = plainText(text);
  return t.length > max ? `${t.slice(0, max)}...` : t;
};

function InfoTile({ label, value, tone = "neutral" }: { label: string; value: string; tone?: "green" | "red" | "neutral" }) {
  const color = tone === "green" ? "text-[#57D7BA]" : tone === "red" ? "text-[#FF5C6C]" : "text-cream";
  return (
    <div className="min-w-0 rounded-md bg-card/55 px-3 py-2.5 ring-1 ring-inset ring-line">
      <div className="text-[10.5px] font-semibold uppercase tracking-wide text-neutral-500">{label}</div>
      <div className={`mt-1 truncate text-[15px] font-bold ${color}`}>{value}</div>
    </div>
  );
}

function YtInvestorSummary({ segments, digest, judgment, zh }: { segments: YtSeg[]; digest?: YtDigest; judgment?: KolJudgment; zh: boolean }) {
  const speech = speechSegments(segments);
  const summary = digest?.summary ?? [];
  const chapters = digest?.chapters?.length ? digest.chapters : [];
  const sections = chapters.length
    ? chapters.map((chapter, ci) => {
        const start = Math.max(0, Math.min(chapter.seg, speech.length - 1));
        const next = chapters[ci + 1]?.seg ?? speech.length;
        return {
          ci,
          title: (zh ? chapter.title.zh : chapter.title.en) || chapter.title.zh || chapter.title.en,
          speech: speech.slice(start, Math.max(start + 1, Math.min(next, speech.length))),
        };
      })
    : [{ ci: 0, title: zh ? "完整观点" : "Full thesis", speech }];
  const horizon = judgment?.horizon ? (zh ? judgment.horizon.zh : judgment.horizon.en) : "";
  const bucket = judgment?.bucket ? (zh ? BUCKET_LABEL[judgment.bucket].zh : BUCKET_LABEL[judgment.bucket].en) : "";
  const target = fmtRange(judgment?.sellLo, judgment?.sellHi);
  const buy = fmtRange(judgment?.buyLo, judgment?.buyHi);

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-1.5 text-[13px] font-bold uppercase tracking-wide text-[#57D7BA]">
        <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
          <path d="M9 11l3 3L22 4M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11" />
        </svg>
        {zh ? "投资者摘要" : "Investor summary"}
      </div>

      {summary.length > 0 && (
        <ul className="space-y-2">
          {summary.map((b, i) => (
            <li key={i} className="flex gap-2.5 text-[15px] leading-relaxed text-neutral-100">
              <span className="mt-[8px] h-1.5 w-1.5 shrink-0 rounded-full bg-[#57D7BA]" />
              <span>{readableInline(zh ? b.zh : b.en)}</span>
            </li>
          ))}
        </ul>
      )}

      <div className="grid grid-cols-2 gap-2 xl:grid-cols-4">
        <InfoTile label={zh ? "目标 / 卖出区" : "Target / sell zone"} value={target || (zh ? "未明确" : "Not stated")} tone={target ? "red" : "neutral"} />
        <InfoTile label={zh ? "买入区" : "Buy zone"} value={buy || (zh ? "未明确" : "Not stated")} tone={buy ? "green" : "neutral"} />
        <InfoTile label={zh ? "时间周期" : "Horizon"} value={horizon || (zh ? "未明确" : "Not stated")} />
        <InfoTile label={zh ? "周期档位" : "Bucket"} value={bucket || (zh ? "未明确" : "Not stated")} />
      </div>

      {judgment?.priceRaw && (
        <div className="rounded-md border-l-2 border-[#57D7BA] bg-[#57D7BA]/[0.055] px-3 py-2 text-[12.5px] leading-relaxed text-neutral-300">
          <span className="mr-1.5 font-semibold text-[#57D7BA]">{zh ? "价格原话" : "Price wording"}</span>
          {judgment.priceRaw}
        </div>
      )}

      {sections.length > 0 && (
        <div className="space-y-2.5">
          <div className="text-[11px] font-semibold uppercase tracking-wide text-neutral-500">
            {zh ? "观点脉络" : "Argument map"}
          </div>
          <div className="grid gap-2">
            {sections.slice(0, 8).map((section, idx) => (
              <div
                key={`${section.ci}-${idx}`}
                data-ch={section.ci}
                className="group flex gap-2 rounded-md bg-card/45 px-3 py-2.5 ring-1 ring-inset ring-line transition hover:bg-elevated/70 hover:ring-[#57D7BA]/40"
              >
                <span className="mt-0.5 flex h-5 min-w-5 items-center justify-center rounded bg-[#57D7BA]/10 font-mono text-[11px] font-bold text-[#57D7BA] ring-1 ring-inset ring-[#57D7BA]/30">
                  {String(idx + 1).padStart(2, "0")}
                </span>
                <span className="min-w-0">
                  <span className="block text-[13px] font-bold leading-snug text-neutral-100 group-hover:text-[#57D7BA]">{section.title}</span>
                  <span className="mt-1 line-clamp-2 block text-[12.5px] leading-relaxed text-neutral-500">
                    {excerpt(section.speech.map((s) => s.text).join("\n\n"))}
                  </span>
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

export function YtReader({
  segments,
  digest,
  judgment,
  zh,
  noCollapse,
}: {
  segments: YtSeg[];
  digest?: YtDigest;
  judgment?: KolJudgment;
  zh: boolean;
  noCollapse?: boolean;
}) {
  const chapters = digest?.chapters ?? [];
  const rootRef = useRef<HTMLDivElement>(null);
  const bodyRef = useRef<HTMLDivElement>(null);
  const [expanded, setExpanded] = useState(false);
  const [mode, setMode] = useState<ReaderMode>("summary");
  // 默认折叠（needsCollapse=true 起步，避免水合时先闪一下全文）；挂载后量一次：内容没超过约一屏就不折叠。
  // noCollapse=true（外层已有固定高度滚动容器，如观点浏览器右侧阅读面板）→ 不折叠，口播全量铺开、由外层滚动。
  const [needsCollapse, setNeedsCollapse] = useState(!noCollapse);

  useEffect(() => {
    if (noCollapse) { setNeedsCollapse(false); return; }
    const el = bodyRef.current;
    if (!el) return;
    const max = window.innerHeight * 0.72; // ≈ 一屏
    setNeedsCollapse(el.scrollHeight > max + 48);
  }, [segments, noCollapse, mode]);

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
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2 border-b border-line/70 pb-2.5">
        <div className="inline-flex rounded-md bg-card/70 p-1 ring-1 ring-inset ring-line">
          {([
            ["summary", zh ? "投资者摘要" : "Investor summary"],
            ["raw", zh ? "原始口播" : "Raw transcript"],
          ] as const).map(([key, label]) => (
            <button
              key={key}
              type="button"
              onClick={() => {
                setMode(key);
                setExpanded(false);
                setTimeout(backToTop, 20);
              }}
              aria-pressed={mode === key}
              className={`h-7 rounded px-2.5 text-[12px] font-semibold transition ${
                mode === key
                  ? "bg-[#57D7BA]/10 text-cream ring-1 ring-inset ring-[#57D7BA]/65"
                  : "text-neutral-500 hover:bg-white/[.035] hover:text-neutral-200"
              }`}
            >
              {label}
            </button>
          ))}
        </div>
        <div className="text-[11px] text-neutral-600">
          {mode === "summary"
            ? (zh ? "摘要层：核心观点、目标价、周期与观点脉络" : "Summary layer: thesis, targets, horizon, argument map")
            : (zh ? "核对层：按原始口播顺序展示" : "Audit layer: original transcript order")}
        </div>
      </div>

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
              {mode === "summary" ? (
                <YtInvestorSummary segments={segments} digest={digest} judgment={judgment} zh={zh} />
              ) : (
                <YtFullContent segments={segments} chapters={chapters} zh={zh} />
              )}
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
