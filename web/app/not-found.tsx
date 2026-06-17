import Link from "next/link";

const BASE = process.env.NEXT_PUBLIC_BASE_PATH || "";

// 品牌化 404：静态导出会生成 out/404.html，托管平台对未知路径回退到它。
export default function NotFound() {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center px-6 text-center bg-ink">
      <span className="w-16 h-16 rounded-2xl overflow-hidden bg-white ring-1 ring-white/10 mb-6">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={`${BASE}/logo.png`} alt="redditalpha" className="w-full h-full object-contain" />
      </span>
      <div className="font-display font-extrabold text-reddit text-[64px] leading-none tracking-tight">404</div>
      <h1 className="mt-3 font-display font-bold text-cream text-xl">页面走丢了 · Page not found</h1>
      <p className="mt-2 text-sm text-neutral-500 max-w-sm leading-relaxed">
        你要找的页面可能已被移动或不存在。
        <br />
        The page you’re looking for doesn’t exist or has moved.
      </p>
      <div className="mt-7 flex items-center gap-3">
        <Link
          href="/zh/"
          className="rounded-xl px-5 py-2.5 font-display font-bold text-white text-sm shadow-lg shadow-reddit/30 ring-1 ring-inset ring-white/15 hover:brightness-110 transition"
          style={{ backgroundImage: "var(--grad-brand)" }}
        >
          返回首页
        </Link>
        <Link
          href="/en/"
          className="rounded-xl px-5 py-2.5 text-sm text-neutral-300 ring-1 ring-inset ring-line hover:text-cream hover:bg-white/[.04] transition"
        >
          English
        </Link>
      </div>
    </div>
  );
}
