import type { MetadataRoute } from "next";
import { SITE_URL, BASE_PATH } from "@/lib/site";
import { locales } from "@/lib/i18n";
import { getGrTickerSymbols } from "@/lib/globalQueries";
import { REGION_ORDER } from "@/lib/regions";
import { getNarrativeSlugs } from "@/lib/narrativeRotation";

export const dynamic = "force-static";

// Prismo 站点地图：语言 ×（总览/标的/区域/搜索 + 各标的 + 各地区）。
// 标的从 gr_ticker 取；缺数据时只剩静态路由。账号/设置等私有页不收录。
export default function sitemap(): MetadataRoute.Sitemap {
  const base = `${SITE_URL}${BASE_PATH}`;
  const now = new Date();
  const staticPaths = ["", "/dashboard", "/narratives", "/tickers", "/regions", "/search"];
  const symbols = getGrTickerSymbols();
  const narratives = getNarrativeSlugs();

  const out: MetadataRoute.Sitemap = [];
  for (const lang of locales) {
    for (const p of staticPaths) {
      out.push({ url: `${base}/${lang}${p}/`, lastModified: now, changeFrequency: "daily", priority: p === "" ? 1 : 0.7 });
    }
    for (const r of REGION_ORDER) {
      out.push({ url: `${base}/${lang}/regions/${r}/`, lastModified: now, changeFrequency: "daily", priority: 0.6 });
    }
    for (const n of narratives) {
      out.push({ url: `${base}/${lang}/narratives/${n}/`, lastModified: now, changeFrequency: "daily", priority: 0.6 });
    }
    for (const s of symbols) {
      out.push({ url: `${base}/${lang}/tickers/${s}/`, lastModified: now, changeFrequency: "daily", priority: 0.5 });
    }
  }
  return out;
}
