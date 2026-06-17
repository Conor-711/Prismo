import type { Metadata } from "next";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { IconArrow } from "@/components/icons";
import { isLocale, defaultLocale, type Locale } from "@/lib/i18n";

// Prismo 占位首页（重构第一步）。旧的 Reddit 落地页已移除；
// 新产品聚合 5 个本土社区，UI 将在后续步骤围绕此重建。
const COMMUNITIES = [
  { name: "Reddit", zh: "美国 · Reddit", en: "US · Reddit" },
  { name: "Yahoo Finance JP", zh: "日本 · Yahoo Finance", en: "Japan · Yahoo Finance" },
  { name: "Naver", zh: "韩国 · Naver", en: "Korea · Naver" },
  { name: "Xueqiu", zh: "中国大陆 · 雪球", en: "China · Xueqiu" },
  { name: "PTT", zh: "台湾 · PTT", en: "Taiwan · PTT" },
];

export function generateMetadata({ params }: { params: { lang: string } }): Metadata {
  const zh = params.lang === "zh";
  return {
    title: "Prismo",
    description: zh
      ? "聚合 Reddit、Yahoo Finance Japan、Naver、雪球、PTT 五大本土社区的散户舆情。"
      : "Cross-community retail sentiment across Reddit, Yahoo Finance Japan, Naver, Xueqiu and PTT.",
  };
}

export default function Home({ params }: { params: { lang: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";

  return (
    <div className="min-h-[70vh] flex flex-col items-center justify-center text-center px-4 py-16">
      <div className="w-full max-w-2xl mx-auto">
        {/* 品牌 */}
        <div className="inline-flex items-center gap-2.5">
          <span
            className="grid place-items-center w-10 h-10 rounded-xl text-white font-display font-extrabold ring-1 ring-inset ring-white/15"
            style={{ backgroundImage: "var(--grad-brand)" }}
          >
            P
          </span>
          <span className="font-display font-extrabold text-cream text-[26px] tracking-tight">Prismo</span>
        </div>

        {/* 状态标签 */}
        <div className="mt-6 inline-flex items-center gap-2 rounded-full px-3 py-1.5 text-[12px] font-semibold ring-1 ring-inset ring-line bg-card text-neutral-400">
          {zh ? "重建中 · 全新升级" : "Rebuilding · major upgrade"}
        </div>

        {/* 标题 */}
        <h1 className="mt-5 font-display font-extrabold text-cream tracking-tight leading-[1.15] text-[clamp(24px,5vw,40px)]">
          {zh ? "五大本土社区的" : "Cross-community retail "}
          <span className="metal-text m-gold">{zh ? "散户舆情聚合" : "sentiment, unified"}</span>
        </h1>

        <p className="mt-4 mx-auto max-w-lg text-neutral-400 leading-relaxed text-[15px] sm:text-[16px]">
          {zh
            ? "Prismo 把 Reddit、Yahoo Finance Japan、Naver、雪球、PTT 五个本土投资社区的真实讨论聚合、分析、对比，呈现同一标的在不同市场的情绪分歧。"
            : "Prismo aggregates, analyzes and contrasts real discussion across five native investing communities — Reddit, Yahoo Finance Japan, Naver, Xueqiu and PTT — revealing how sentiment on the same ticker diverges across markets."}
        </p>

        {/* 五大社区 */}
        <div className="mt-7 flex flex-wrap items-center justify-center gap-2">
          {COMMUNITIES.map((c) => (
            <span
              key={c.name}
              className="inline-flex items-center rounded-full px-3 py-1.5 text-[12px] font-medium ring-1 ring-inset ring-line bg-card text-neutral-300"
            >
              {zh ? c.zh : c.en}
            </span>
          ))}
        </div>

        {/* 进入现有 5 地区看板 */}
        <div className="mt-9 flex flex-col items-center gap-3">
          <LocaleLink
            href="/lab/global-retail"
            className="group inline-flex items-center justify-center gap-2 rounded-xl px-6 py-3.5 font-display font-bold text-white text-[15px] shadow-lg ring-1 ring-inset ring-white/15 hover:brightness-110 hover:-translate-y-0.5 transition"
            style={{ backgroundImage: "var(--grad-brand)" }}
          >
            {zh ? "进入五地区看板" : "Enter the 5-region dashboard"}
            <IconArrow className="w-4 h-4 transition group-hover:translate-x-0.5" />
          </LocaleLink>
          <p className="text-[13px] text-neutral-500">
            {zh ? "全新 Prismo 体验正在搭建中。" : "The new Prismo experience is under construction."}
          </p>
        </div>
      </div>
    </div>
  );
}
