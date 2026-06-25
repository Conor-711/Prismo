import { Module } from "@/components/prismo/DetailBits";
import type { Locale } from "@/lib/i18n";
import type { YtVideoRow, YtSummaryRow } from "@/lib/youtubeQueries";

// 标的页「YouTube 观点」模块：近 24h 全语种财经视频，Gemini 看完/读字幕总结。
// 服务端组件（构建期读 dev.db）；无视频则整块不渲染（return null）。

const LANG_FLAG: Record<string, string> = {
  en: "🇺🇸", ko: "🇰🇷", ja: "🇯🇵", zh: "🇨🇳", "zh-TW": "🇹🇼", "zh-HK": "🇭🇰",
  de: "🇩🇪", es: "🇪🇸", fr: "🇫🇷", pt: "🇧🇷", hi: "🇮🇳", vi: "🇻🇳",
};
function flagOf(lang: string): string {
  return LANG_FLAG[lang] || LANG_FLAG[(lang || "").slice(0, 2)] || "🌐";
}
function fmtViews(n: number): string {
  return n >= 1e6 ? (n / 1e6).toFixed(1) + "M" : n >= 1e3 ? (n / 1e3).toFixed(0) + "K" : String(n);
}
function dur(s: number): string {
  const m = Math.floor(s / 60);
  return m >= 60 ? `${Math.floor(m / 60)}h${m % 60}m` : `${m}m`;
}
const STANCE: Record<string, { zh: string; en: string; cls: string }> = {
  bull: { zh: "看多", en: "Bull", cls: "text-bull bg-bull/10 ring-bull/25" },
  bear: { zh: "看空", en: "Bear", cls: "text-bear bg-bear/10 ring-bear/25" },
  neutral: { zh: "中性", en: "Neutral", cls: "text-neutral-300 bg-white/5 ring-line" },
};

export function YouTubeOpinions({
  videos, summary, lang,
}: { videos: YtVideoRow[]; summary: YtSummaryRow | null; lang: Locale }) {
  const zh = lang === "zh";
  if (!videos.length) return null;
  const net = summary?.net_sentiment ?? 0;

  return (
    <Module title={zh ? "YouTube 观点" : "YouTube takes"} icon="trend" accent="reddit"
      hint={zh ? "近 24h 全语种财经视频 · Gemini 看完总结（纳入当地分析者）"
               : "last 24h finance videos, all languages · Gemini-summarized"}>
      {summary && (
        <div className="flex flex-wrap items-center gap-x-5 gap-y-2 pb-3 mb-3 border-b border-line text-[12px]">
          <span className="text-neutral-500">{zh ? "净观点" : "Net"} <span className={net >= 0 ? "text-bull" : "text-bear"}>{(net > 0 ? "+" : "") + net.toFixed(2)}</span></span>
          <span className="text-bull">{zh ? "看多" : "Bull"} {summary.bull_count}</span>
          <span className="text-bear">{zh ? "看空" : "Bear"} {summary.bear_count}</span>
          <span className="text-neutral-400">{zh ? "中性" : "Neutral"} {summary.neutral_count}</span>
          <span className="text-neutral-500 ml-auto">{summary.video_count} {zh ? "条 · " : "vids · "}{fmtViews(summary.total_views)} {zh ? "次播放" : "views"}</span>
        </div>
      )}
      <div className="grid sm:grid-cols-2 gap-3">
        {videos.map((v) => {
          const st = STANCE[v.stance] || STANCE.neutral;
          const sm = zh ? (v.summary_zh || v.summary_en) : (v.summary_en || v.summary_zh);
          const kp = (zh
            ? (v.key_points_zh.length ? v.key_points_zh : v.key_points_en)
            : (v.key_points_en.length ? v.key_points_en : v.key_points_zh)
          ).filter(Boolean).slice(0, 3);
          return (
            <a key={v.id} href={v.url} target="_blank" rel="noopener noreferrer"
               className="block rounded-lg bg-white/[.02] ring-1 ring-inset ring-line p-3 hover:bg-white/[.04] transition">
              <div className="flex items-center justify-between gap-2 mb-1.5">
                <span className="inline-flex items-center gap-1.5 text-[12px] text-neutral-300 min-w-0">
                  <span className="shrink-0">{flagOf(v.lang)}</span><span className="truncate">{v.channel}</span>
                </span>
                <span className={`shrink-0 text-[10px] px-1.5 py-0.5 rounded ring-1 ring-inset ${st.cls}`}>{zh ? st.zh : st.en}</span>
              </div>
              <div className="text-[13px] text-cream font-medium leading-snug line-clamp-2">{v.title}</div>
              {sm && <p className="mt-1.5 text-[12px] text-neutral-400 leading-relaxed line-clamp-3">{sm}</p>}
              {kp.length > 0 && (
                <ul className="mt-1.5 space-y-0.5">
                  {kp.map((p, i) => (
                    <li key={i} className="flex gap-1.5 text-[11px] text-neutral-500 leading-snug">
                      <span className="mt-[5px] h-1 w-1 shrink-0 rounded-full bg-neutral-600" />
                      <span className="min-w-0 line-clamp-2">{p}</span>
                    </li>
                  ))}
                </ul>
              )}
              <div className="mt-2 flex items-center gap-x-3 text-[10px] text-neutral-600">
                <span>▶ {fmtViews(v.view_count)}</span>
                <span>{dur(v.duration_s)}</span>
                {v.price_target && <span className="text-amber">🎯 {v.price_target}</span>}
                <span className="ml-auto text-neutral-700">{v.mode === "video" ? (zh ? "看视频" : "video") : v.mode === "text" ? (zh ? "标题简介" : "title") : (zh ? "字幕" : "transcript")}</span>
              </div>
            </a>
          );
        })}
      </div>
    </Module>
  );
}
