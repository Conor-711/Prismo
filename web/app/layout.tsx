import type { Metadata, Viewport } from "next";
import "./globals.css";
import { AuthProvider } from "@/components/auth/AuthProvider";
import { FavoritesProvider } from "@/components/favorites/FavoritesProvider";
import { PwaRegister } from "@/components/PwaRegister";
import { SITE_URL, BASE_PATH, OG_IMAGE } from "@/lib/site";

// 防闪烁：首屏渲染前按 localStorage 套用主题类 + 侧边栏折叠状态（默认白天 / 展开），
// 并同步浏览器 UI 的 theme-color（移动端状态栏配色随主题）。
const THEME_INIT = `try{var d=document.documentElement;var t=localStorage.getItem('redditalpha:theme');var dark=t==='dark';if(dark){d.classList.add('dark')}else{d.classList.remove('dark')}var sb=localStorage.getItem('redditalpha:sidebar');if(sb){d.setAttribute('data-sb',sb)}var m=document.querySelector('meta[name=theme-color]');if(m){m.setAttribute('content',dark?'#0b0b0d':'#f4f5f7')}var lp=location.pathname.split('/')[1];var LM={zh:'zh-CN',en:'en',ja:'ja',ko:'ko'};if(LM[lp]){d.lang=LM[lp]}}catch(e){}`;

// 移动端适配：随设备宽度自适应 + 覆盖刘海安全区（配合 sticky/fixed 元素的 env(safe-area-*) 留白）。
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: "#f4f5f7", // 默认白天；THEME_INIT / ThemeToggle 会按实际主题改为深色
};

const SITE_TITLE = "redditalpha · Reddit 美股舆情情报";
const SITE_DESC =
  "以专业方式分析 Reddit 财经板块的帖子数据：声量份额、情绪、异动、热门叙事与每日简报。";

export const metadata: Metadata = {
  metadataBase: new URL(`${SITE_URL}${BASE_PATH}`),
  title: SITE_TITLE,
  description: SITE_DESC,
  applicationName: "redditalpha",
  manifest: `${BASE_PATH}/manifest.webmanifest`,
  appleWebApp: { capable: true, statusBarStyle: "black-translucent", title: "redditalpha" },
  formatDetection: { telephone: false },
  openGraph: {
    type: "website",
    siteName: "redditalpha",
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
    <html lang="zh-CN" suppressHydrationWarning>
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
