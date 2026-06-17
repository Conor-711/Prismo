import type { MetadataRoute } from "next";
import { SITE_URL, BASE_PATH } from "@/lib/site";

export const dynamic = "force-static";

// 静态导出会生成 out/robots.txt。允许收录公开内容，屏蔽登录/账户/后台等私有页，并指向站点地图。
export default function robots(): MetadataRoute.Robots {
  const base = `${SITE_URL}${BASE_PATH}`;
  return {
    rules: {
      userAgent: "*",
      allow: "/",
      disallow: [
        "/*/insights",
        "/*/account",
        "/*/login",
        "/*/signup",
        "/*/forgot-password",
        "/*/reset-password",
        "/*/onboarding",
        "/*/auth",
      ],
    },
    sitemap: `${base}/sitemap.xml`,
  };
}
