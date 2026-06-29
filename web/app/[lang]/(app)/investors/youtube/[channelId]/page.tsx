import type { Metadata } from "next";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { CreatorProfile } from "@/components/prismo/CreatorProfile";
import { getYoutubeCreator, getYoutubeChannelIds } from "@/lib/creatorQueries";
import { isLocale, defaultLocale, type Locale } from "@/lib/i18n";

// YouTube 作者页（投资者榜单的下钻）。静态导出：枚举所有有视频的频道 id；[lang] 由 layout 提供。
export const dynamicParams = false;
export function generateStaticParams() {
  const ids = getYoutubeChannelIds();
  // 空快照兜底：返回占位 id，避免 output:export 因空数组报错（该页走空态）。
  return (ids.length ? ids : ["_none"]).map((channelId) => ({ channelId }));
}

export function generateMetadata({ params }: { params: { lang: string; channelId: string } }): Metadata {
  const zh = params.lang === "zh";
  const c = getYoutubeCreator(params.channelId);
  const name = c?.profile.name || (zh ? "作者" : "Creator");
  return { title: `${name} · YouTube · Prismo` };
}

export default function YoutubeCreatorPage({ params }: { params: { lang: string; channelId: string } }) {
  const lang: Locale = isLocale(params.lang) ? params.lang : defaultLocale;
  const zh = lang === "zh";
  const creator = getYoutubeCreator(params.channelId);

  return (
    <div className="space-y-5">
      <LocaleLink href="/investors" className="inline-flex items-center gap-1 text-xs text-neutral-500 transition hover:text-cream">
        ← {zh ? "投资者榜单" : "Investors"}
      </LocaleLink>
      {creator ? (
        <CreatorProfile creator={creator} zh={zh} />
      ) : (
        <div className="panel rounded-xl p-10 text-center">
          <p className="text-sm text-neutral-400">{zh ? "暂无该作者数据" : "No data for this creator"}</p>
          <p className="mt-2 text-xs text-neutral-600">
            {zh ? "在本地运行数据管线后重新构建站点。" : "Run the data pipeline locally, then rebuild the site."}
          </p>
        </div>
      )}
    </div>
  );
}
