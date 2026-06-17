"use client";

import { useEffect, useState } from "react";
import { useLocale } from "./i18n/LocaleProvider";

const KEY = "redditalpha:bookmark-hint";

// 首次进入站点时，指向浏览器右上角「收藏/书签」星标的引导箭头。
// 用户点关闭或「知道了」后写入 localStorage，不再显示。
export function BookmarkHint() {
  const { dict } = useLocale();
  const t = dict.bookmark;
  const [show, setShow] = useState(false);
  const [combo, setCombo] = useState("Ctrl + D");

  useEffect(() => {
    try {
      if (localStorage.getItem(KEY)) return;
    } catch {
      /* privacy mode */
    }
    // 仅桌面端：移动端改用「加到主屏」提醒(InstallPrompt)，避免指向不存在的浏览器星标。
    try {
      if (matchMedia("(max-width: 1023px)").matches) return;
    } catch {
      /* ignore */
    }
    const ua = (navigator.platform || navigator.userAgent || "").toLowerCase();
    const mac = /mac|iphone|ipad|ipod/.test(ua);
    setCombo(mac ? "⌘ D" : "Ctrl + D");
    setShow(true);
  }, []);

  const dismiss = () => {
    try {
      localStorage.setItem(KEY, "1");
    } catch {
      /* ignore */
    }
    setShow(false);
  };

  if (!show) return null;

  const [subPre, subPost] = t.sub.split("{combo}");

  return (
    <div className="fixed top-0.5 z-[80] pointer-events-none flex flex-col items-end right-3 sm:right-[27rem]">
      {/* 上指箭头 → 浏览器地址栏右侧的「收藏 ★」星标。
          星标到窗口右缘的距离≈固定(扩展图标右对齐)，故用固定 rem 偏移比百分比更稳。 */}
      <div className="pr-3 sm:pr-1 text-reddit animate-bounce drop-shadow-[0_2px_6px_rgba(252,62,2,.5)]">
        <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
          <path d="M12 20V5M5 12l7-7 7 7" />
        </svg>
      </div>

      {/* 提示卡 */}
      <div
        className="pointer-events-auto mt-1 w-[268px] panel rounded-xl p-3.5 pr-9 relative"
        style={{ boxShadow: "inset 0 0 0 1px rgba(252,62,2,.32), 0 12px 34px rgba(0,0,0,.5)" }}
      >
        <button
          onClick={dismiss}
          aria-label={t.close}
          className="absolute top-2 right-2 grid place-items-center w-6 h-6 rounded-md text-neutral-500 hover:text-cream hover:bg-white/10 transition"
        >
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.3" strokeLinecap="round" aria-hidden>
            <path d="M6 6l12 12M18 6L6 18" />
          </svg>
        </button>

        <div className="flex items-center gap-1.5">
          <span className="text-gold text-[15px] leading-none">★</span>
          <span className="font-display font-bold text-cream text-sm">{t.tip}</span>
        </div>
        <p className="mt-1.5 text-[12px] text-neutral-400 leading-relaxed">
          {subPre}
          <kbd className="mx-0.5 px-1.5 py-0.5 rounded bg-white/10 text-cream font-mono text-[11px] ring-1 ring-inset ring-white/15 whitespace-nowrap">
            {combo}
          </kbd>
          {subPost}
        </p>
        <button onClick={dismiss} className="mt-2.5 text-[12px] font-semibold text-reddit hover:underline">
          {t.dismiss}
        </button>
      </div>
    </div>
  );
}
