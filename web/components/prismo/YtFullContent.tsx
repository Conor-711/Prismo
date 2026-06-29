"use client";

// YouTube 口播转录的阅读视图。数据 = yt_fulltext.segments（pipeline youtube-fulltext：Gemini 口播完整还原）。
// Gemini 已按语义分段、并在 text 里用 Markdown 标重点（**加粗** / *斜体*）。
// 单人(独白) → 干净分段长文（限行宽）。多人(访谈/播客) → 按说话人分回合的对话排版。
// 若传入 chapters（yt_digest 内容目录），在对应 speech 段前埋**章节标题 + 锚点**（data-ch），供右侧目录跳转。
import { Fragment, type ReactNode } from "react";
import type { YtSeg, YtChapter } from "@/lib/mockDetail";

// 行内 Markdown 渲染：**加粗** / *斜体*（轻量，无需第三方库）。
function inline(text: string): ReactNode[] {
  const out: ReactNode[] = [];
  const re = /\*\*([^*]+?)\*\*|\*([^*\n]+?)\*/g;
  let last = 0, k = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) out.push(text.slice(last, m.index));
    if (m[1] != null) out.push(<strong key={k++} className="font-semibold text-cream">{m[1]}</strong>);
    else out.push(<em key={k++} className="italic text-neutral-300">{m[2]}</em>);
    last = re.lastIndex;
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}

// 一段口播 → 段落（按空行再细分）+ 行内强调。返回 Fragment，使外层 space-y 对所有 <p> 统一生效。
function RichText({ text }: { text: string }) {
  const paras = text.split(/\n{2,}/).map((p) => p.trim()).filter(Boolean);
  if (!paras.length) return null;
  return (
    <>
      {paras.map((p, i) => (
        <p key={i} className="text-[14px] leading-[1.8] text-neutral-200">{inline(p)}</p>
      ))}
    </>
  );
}

// 章节标题 + 跳转锚点（data-ch=章节序号）；scroll-mt 让 smooth scroll 后标题不贴顶。
function ChapterHead({ title, ci }: { title: string; ci: number }) {
  return (
    <div data-ch={ci} className="mb-1.5 mt-6 scroll-mt-6 text-[12.5px] font-semibold text-[#57D7BA] first:mt-0">
      {title}
    </div>
  );
}

// 说话人配色：避开蓝紫 AI 味（暖色 / 中性 / 青绿），按名字哈希确定性取色。
const SPEAKER_COLORS = ["#57D7BA", "#E0A458", "#C98BB9", "#7FB685", "#D98695"];
function speakerColor(name: string): string {
  let h = 0;
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) >>> 0;
  return SPEAKER_COLORS[h % SPEAKER_COLORS.length];
}
function initial(name: string): string {
  const t = name.trim();
  return t ? t[0].toUpperCase() : "·"; // 中文取首字 / 英文取首字母
}

type Speech = { type: "speech"; text: string; speaker?: string };
type Turn = { speaker: string; texts: string[]; start: number }; // speaker="" = 无说话人(独白)；start=该回合首句的 speech 全局下标

// 把有序口播段落折成「回合」：同一说话人连续讲话合并为一回合，标签只出现一次。start 记录回合首句的全局下标。
function toTurns(speech: Speech[]): Turn[] {
  const turns: Turn[] = [];
  speech.forEach((s, gi) => {
    const spk = (s.speaker || "").trim();
    const last = turns[turns.length - 1];
    if (last && last.speaker === spk) last.texts.push(s.text);
    else turns.push({ speaker: spk, texts: [s.text], start: gi });
  });
  return turns;
}

export function YtFullContent({ segments, chapters, zh }: { segments: YtSeg[]; chapters?: YtChapter[]; zh: boolean }) {
  const speech = (segments || []).filter((s): s is Speech => s.type === "speech");
  if (!speech.length) return null;
  const turns = toTurns(speech);
  const isDialogue = new Set(turns.map((t) => t.speaker).filter(Boolean)).size >= 2;

  // chapter seg(speech 下标) → 章节序号；用于在对应段落前插标题锚点。
  const chBySeg = new Map<number, number>();
  (chapters || []).forEach((c, ci) => { if (typeof c.seg === "number") chBySeg.set(c.seg, ci); });
  const headFor = (segIdx: number) => {
    const ci = chBySeg.get(segIdx);
    if (ci == null) return null;
    const t = zh ? chapters![ci].title.zh : chapters![ci].title.en;
    return <ChapterHead title={t || chapters![ci].title.zh || chapters![ci].title.en} ci={ci} />;
  };

  return (
    <div>
      {/* 头部：转录标识 */}
      <div className="mb-3 flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide text-neutral-500">
        <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
          <path d="M4 6h16M4 12h16M4 18h10" />
        </svg>
        {zh ? "完整口播" : "Full transcript"}
        {isDialogue && <span className="font-normal normal-case text-neutral-600">· {zh ? "多人对话" : "Dialogue"}</span>}
      </div>

      {isDialogue ? (
        // 多人：按说话人分回合的对话排版；章节标题在「包含该 seg 的回合」前插入（snap 到回合边界）
        <div className="space-y-5">
          {turns.map((t, i) => {
            const color = t.speaker ? speakerColor(t.speaker) : "#8a8f98";
            // 该回合覆盖的 speech 下标区间 [start, start+len) 内若有章节起点 → 取最靠前的一个先插标题
            let head: ReactNode = null;
            for (let g = t.start; g < t.start + t.texts.length; g++) {
              const h = headFor(g);
              if (h) { head = h; break; }
            }
            return (
              <Fragment key={i}>
                {head}
                <div className="flex gap-3">
                  <span
                    className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-[12px] font-bold"
                    style={{ backgroundColor: color + "22", color }}
                  >
                    {initial(t.speaker)}
                  </span>
                  <div className="min-w-0 flex-1">
                    {t.speaker && (
                      <div className="mb-1 text-[12.5px] font-semibold" style={{ color }}>{t.speaker}</div>
                    )}
                    <div className="space-y-2.5">
                      {t.texts.map((tx, j) => <RichText key={j} text={tx} />)}
                    </div>
                  </div>
                </div>
              </Fragment>
            );
          })}
        </div>
      ) : (
        // 单人：干净分段长文。章节标题在对应 speech 下标的段落前插入（j == speech 全局下标）。
        <div className={`max-w-[68ch] ${chBySeg.size ? "space-y-3" : "space-y-3.5 border-l-2 border-line/60 pl-4"}`}>
          {turns.flatMap((t) => t.texts).map((tx, j) => (
            <Fragment key={j}>
              {headFor(j)}
              <RichText text={tx} />
            </Fragment>
          ))}
        </div>
      )}
    </div>
  );
}
