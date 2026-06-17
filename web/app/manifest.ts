import type { MetadataRoute } from "next";

// PWA manifest（Next 静态导出会生成 /manifest.webmanifest）。
// 配合 viewport.themeColor + appleWebApp + sw.js，实现「可加到主屏 / 全屏启动」。
export const dynamic = "force-static";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "redditalpha · Reddit 美股舆情情报",
    short_name: "redditalpha",
    description: "Reddit 美股 + 中概股舆情情报看板：声量 / 情绪 / 异动 / 主导叙事 / 每日简报。",
    start_url: "/",
    scope: "/",
    display: "standalone",
    orientation: "portrait",
    background_color: "#09090b",
    theme_color: "#09090b",
    lang: "zh-CN",
    categories: ["finance", "news", "productivity"],
    icons: [
      { src: "/icon-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
      { src: "/icon-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
      { src: "/icon-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
    ],
  };
}
