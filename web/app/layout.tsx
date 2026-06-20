import type { Metadata, Viewport } from "next";
import "./globals.css";
import { AuthProvider } from "@/components/auth/AuthProvider";
import { FavoritesProvider } from "@/components/favorites/FavoritesProvider";
import { PwaRegister } from "@/components/PwaRegister";
import { SITE_URL, BASE_PATH, OG_IMAGE } from "@/lib/site";

// 初始化：强制深色主题（已停用白天模式）+ 套用侧边栏折叠状态 + 按路径设 <html lang>。
const THEME_INIT = `try{var d=document.documentElement;d.classList.add('dark');var sb=localStorage.getItem('prismo:sidebar');if(sb){d.setAttribute('data-sb',sb)}var lp=location.pathname.split('/')[1];var LM={zh:'zh-CN',en:'en',ja:'ja',ko:'ko'};if(LM[lp]){d.lang=LM[lp]}}catch(e){}`;

// 移动端适配：随设备宽度自适应 + 覆盖刘海安全区（配合 sticky/fixed 元素的 env(safe-area-*) 留白）。
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: "#121212", // 深色唯一主题（已停用白天模式）
};

const SITE_TITLE = "Prismo · 多社区美股舆情聚合";
const SITE_DESC =
  "聚合 Reddit、Yahoo Finance Japan、Naver、雪球、PTT 五大本土社区的美股舆情：跨区情绪对比、共识与分歧、代表讨论。";

export const metadata: Metadata = {
  metadataBase: new URL(`${SITE_URL}${BASE_PATH}`),
  title: SITE_TITLE,
  description: SITE_DESC,
  applicationName: "Prismo",
  manifest: `${BASE_PATH}/manifest.webmanifest`,
  appleWebApp: { capable: true, statusBarStyle: "black-translucent", title: "Prismo" },
  formatDetection: { telephone: false },
  openGraph: {
    type: "website",
    siteName: "Prismo",
    title: SITE_TITLE,
    description: SITE_DESC,
    images: [{ url: OG_IMAGE, width: 1200, height: 630 }],
  },
  twitter: {
    card: "summary_large_image",
    title: SITE_TITLE,
    description: SITE_DESC,
    images: [OG_IMAGE],
  },
};

// 根布局只负责 html/body 外壳与全局 Provider；
// 站点 chrome（侧栏/顶栏/信号条）在 app/[lang]/layout.tsx 内，受语言上下文包裹。
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="zh-CN" className="dark" suppressHydrationWarning>
      <body className="bg-ink text-neutral-300 font-sans antialiased">
        <script dangerouslySetInnerHTML={{ __html: THEME_INIT }} />
        <AuthProvider>
          <FavoritesProvider>{children}</FavoritesProvider>
        </AuthProvider>
        <PwaRegister />
      </body>
    </html>
  );
}
