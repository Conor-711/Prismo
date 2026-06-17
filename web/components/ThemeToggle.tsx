"use client";

import { useEffect, useState } from "react";
import { useLocale } from "./i18n/LocaleProvider";

const KEY = "redditalpha:theme";

// variant="fab"：右下角悬浮按钮（仅移动端显示，桌面端用侧边栏内的 inline）
// variant="inline"：嵌入侧边栏下半部分的行内按钮
export function ThemeToggle({ variant = "fab" }: { variant?: "fab" | "inline" }) {
  const { dict } = useLocale();
  const [theme, setTheme] = useState<"dark" | "light">("light");

  useEffect(() => {
    const read = () =>
      setTheme(document.documentElement.classList.contains("dark") ? "dark" : "light");
    read();
    // 同步另一处实例（fab / inline）切换后的状态
    const obs = new MutationObserver(read);
    obs.observe(document.documentElement, { attributes: true, attributeFilter: ["class"] });
    return () => obs.disconnect();
  }, []);

  const toggle = () => {
    const next = theme === "light" ? "dark" : "light";
    setTheme(next);
    document.documentElement.classList.toggle("dark", next === "dark");
    try {
      localStorage.setItem(KEY, next);
    } catch {
      /* ignore */
    }
    // 同步移动端浏览器状态栏配色
    try {
      const m = document.querySelector('meta[name="theme-color"]');
      if (m) m.setAttribute("content", next === "dark" ? "#0b0b0d" : "#f4f5f7");
    } catch {
      /* ignore */
    }
  };

  const fab = variant === "fab";
  const cls = fab
    ? "theme-fab fixed z-[60] lg:hidden grid place-items-center w-11 h-11 rounded-full panel ring-1 ring-inset ring-line text-neutral-400 hover:text-reddit transition hover:-translate-y-0.5"
    : "grid place-items-center w-9 h-9 rounded-full ring-1 ring-inset ring-line bg-white/[.03] text-neutral-400 hover:text-reddit hover:bg-white/[.06] transition shrink-0";
  // fab 抬到底部 Tab 栏之上（含刘海安全区）
  const style = fab ? { right: "1rem", bottom: "calc(4.75rem + env(safe-area-inset-bottom))" } : undefined;

  return (
    <button
      type="button"
      onClick={toggle}
      aria-label={theme === "light" ? dict.chrome.themeToDark : dict.chrome.themeToLight}
      title={theme === "light" ? dict.chrome.themeDark : dict.chrome.themeLight}
      className={cls}
      style={style}
    >
      {theme === "dark" ? <SunIcon /> : <MoonIcon />}
    </button>
  );
}

function SunIcon() {
  return (
    <svg viewBox="0 0 24 24" className="w-5 h-5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="4" />
      <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
    </svg>
  );
}

function MoonIcon() {
  return (
    <svg viewBox="0 0 24 24" className="w-5 h-5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z" />
    </svg>
  );
}
