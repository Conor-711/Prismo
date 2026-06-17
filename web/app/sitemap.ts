import type { MetadataRoute } from "next";
import { SITE_URL, BASE_PATH } from "@/lib/site";
import { locales } from "@/lib/i18n";
import { getAllTickerSymbols, getAllCnTickerSymbols, getAllPostIds, getLeaderboard } from "@/lib/queries";

export const dynamic = "force-static";

// 全站站点地图：语言 ×（看板/搜索/榜单 + 个股 + 帖子）。地址由 SITE_URL(+BASE_PATH) 驱动，
// 部署到不同域名时只需在构建期设 NEXT_PUBLIC_SITE_URL。静态导出会生成 out/sitemap.xml。
export default function sitemap(): MetadataRoute.Sitemap {
  const base = `${SITE_URL}${BASE_PATH}`;
  const now = new Date();

  // 公开内容路由（不含登录/账户/后台看板等私有页）
  const staticPaths: { p: string; cf: "weekly" | "hourly" | "daily"; pr: number }[] = [
    { p: "", cf: "weekly", pr: 0.8 }, // 落地页 /{lang}/
    { p: "/dashboard", cf: "hourly", pr: 1 },
    { p: "/cn", cf: "hourly", pr: 0.9 },
    { p: "/search", cf: "weekly", pr: 0.6 },
    { p: "/cn/search", cf: "weekly", pr: 0.6 },
    { p: "/leaderboard", cf: "daily", pr: 0.6 },
  ];

  const usT = getAllTickerSymbols();
  const cnT = getAllCnTickerSymbols();
  const posts = getAllPostIds();
  // 作者页很多（每个有帖作者都有页），SEO 只收录实力榜 Top 100，避免大量薄页稀释权重。
  const topAuthors = getLeaderboard(100).map((r) => r.author);

  const out: MetadataRoute.Sitemap = [];
  for (const lang of locales) {
    for (const s of staticPaths) {
      out.push({ url: `${base}/${lang}${s.p}/`, lastModified: now, changeFrequency: s.cf, priority: s.pr });
    }
    for (const sym of usT) out.push({ url: `${base}/${lang}/ticker/${sym}/`, lastModified: now, changeFrequency: "daily", priority: 0.6 });
    for (const sym of cnT) out.push({ url: `${base}/${lang}/cn/ticker/${sym}/`, lastModified: now, changeFrequency: "daily", priority: 0.6 });
    for (const id of posts) out.push({ url: `${base}/${lang}/post/${id}/`, lastModified: now, changeFrequency: "weekly", priority: 0.5 });
    for (const a of topAuthors) out.push({ url: `${base}/${lang}/author/${encodeURIComponent(a)}/`, lastModified: now, changeFrequency: "weekly", priority: 0.5 });
  }
  return out;
}
