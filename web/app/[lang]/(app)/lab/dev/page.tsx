import type { Metadata } from "next";
import { DevConsole } from "@/components/DevConsole";

// 隐藏的「测试控制台」：noindex、不进 sitemap、无导航入口。仅 URL /[lang]/lab/dev 直达。
// 一组按钮即时触发/重置各功能自测（onboarding / 收藏 / 埋点 / PWA）。逻辑全在客户端 DevConsole。
export const metadata: Metadata = {
  title: "Dev Console",
  robots: { index: false, follow: false },
};

export default function DevPage() {
  return <DevConsole />;
}
