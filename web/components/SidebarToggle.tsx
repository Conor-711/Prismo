"use client";

import type { ReactNode } from "react";

const KEY = "prismo:sidebar";

type SidebarToggleAction = "toggle" | "collapse" | "expand";

function setSidebarState(collapsed: boolean) {
  const v = collapsed ? "collapsed" : "expanded";
  document.documentElement.setAttribute("data-sb", v);
  try {
    localStorage.setItem(KEY, v);
  } catch {
    /* ignore */
  }
}

function sidebarIsCollapsed() {
  return document.documentElement.getAttribute("data-sb") === "collapsed";
}

// 折叠 / 展开桌面侧边栏：切 <html data-sb>（CSS 在 globals.css 处理位移），并记忆到 localStorage。
export function SidebarToggle({
  action = "toggle",
  className = "hidden lg:grid place-items-center w-8 h-8 rounded-lg text-neutral-400 hover:text-cream hover:bg-white/5 transition shrink-0",
  label,
  children,
}: {
  action?: SidebarToggleAction;
  className?: string;
  label?: string;
  children?: ReactNode;
}) {
  const resolvedLabel = label ?? (action === "expand" ? "展开侧边栏" : action === "collapse" ? "折叠侧边栏" : "切换侧边栏");

  const toggle = () => {
    const next =
      action === "toggle"
        ? !sidebarIsCollapsed()
        : action === "collapse";
    setSidebarState(next);
  };

  return (
    <button
      type="button"
      onClick={toggle}
      aria-label={resolvedLabel}
      title={resolvedLabel}
      className={className}
    >
      {children ?? (
        <svg viewBox="0 0 24 24" className="w-[18px] h-[18px]" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
          <rect x="3" y="4" width="18" height="16" rx="2" />
          <path d="M9 4v16" />
        </svg>
      )}
    </button>
  );
}
