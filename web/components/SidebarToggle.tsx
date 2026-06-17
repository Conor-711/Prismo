"use client";

import { useEffect, useState } from "react";

const KEY = "redditalpha:sidebar";

// 折叠 / 展开桌面侧边栏：切 <html data-sb>（CSS 在 globals.css 处理位移），并记忆到 localStorage。
export function SidebarToggle() {
  const [collapsed, setCollapsed] = useState(false);

  useEffect(() => {
    setCollapsed(document.documentElement.getAttribute("data-sb") === "collapsed");
  }, []);

  const toggle = () => {
    const next = !collapsed;
    setCollapsed(next);
    const v = next ? "collapsed" : "expanded";
    document.documentElement.setAttribute("data-sb", v);
    try {
      localStorage.setItem(KEY, v);
    } catch {
      /* ignore */
    }
  };

  return (
    <button
      type="button"
      onClick={toggle}
      aria-label={collapsed ? "展开侧边栏" : "折叠侧边栏"}
      title={collapsed ? "展开侧边栏" : "折叠侧边栏"}
      className="hidden lg:grid place-items-center w-8 h-8 rounded-lg text-neutral-400 hover:text-cream hover:bg-white/5 transition shrink-0"
    >
      <svg viewBox="0 0 24 24" className="w-[18px] h-[18px]" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <rect x="3" y="4" width="18" height="16" rx="2" />
        <path d="M9 4v16" />
      </svg>
    </button>
  );
}
