import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { AuthorView } from "@/components/author/AuthorView";
import { getAuthorNames, getAuthorDetail } from "@/lib/queries";
import { getDictionary, isLocale, defaultLocale, type Locale } from "@/lib/i18n";
import { SITE_URL, OG_IMAGE } from "@/lib/site";

export const dynamicParams = false;

export function generateStaticParams() {
  return getAuthorNames().map((name) => ({ name }));
}

export function generateMetadata({ params }: { params: { lang: string; name: string } }): Metadata {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const name = params.name;
  const zh = lang === "zh";
  const title = `u/${name} · Reddit ${zh ? "作者画像" : "author profile"} | redditalpha`;
  const desc = zh
    ? `u/${name} 在 Reddit 财经社区的代表作、看好/看空标的与内容画像 —— 由 AI 聚合分析。`
    : `u/${name}'s top DD, bullish/bearish tickers and content profile across Reddit's finance communities, aggregated by AI.`;
  const url = `${SITE_URL}/${lang}/author/${encodeURIComponent(name)}/`;
  return {
    title,
    description: desc,
    alternates: { canonical: url },
    openGraph: { title, description: desc, url, siteName: "redditalpha", type: "profile", images: [{ url: OG_IMAGE, width: 1200, height: 630 }] },
    twitter: { card: "summary_large_image", title, description: desc, images: [OG_IMAGE] },
  };
}

export default function AuthorPage({ params }: { params: { lang: string; name: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const t = getDictionary(lang).author;
  const data = getAuthorDetail(params.name);
  if (!data.stats.posts) notFound();
  return <AuthorView data={data} lang={lang} t={t} />;
}
