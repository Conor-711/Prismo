import type { MetadataRoute } from "next";
import { SITE_URL, BASE_PATH } from "@/lib/site";
import { locales } from "@/lib/i18n";

export const dynamic = "force-static";

// 站点地图（重构期最小集）：仅收录每种语言的占位首页。
// Reddit 单站页面（dashboard/ticker/post/author/leaderboard/search/cn）已移除；
// 5 地区实验页 noindex、暂不收录。围绕 5 社区重建 UI 后再补充。
export default function sitemap(): MetadataRoute.Sitemap {
  const base = `${SITE_URL}${BASE_PATH}`;
  const now = new Date();
  return locales.map((lang) => ({
    url: `${base}/${lang}/`,
    lastModified: now,
    changeFrequency: "weekly" as const,
    priority: 0.8,
  }));
}
