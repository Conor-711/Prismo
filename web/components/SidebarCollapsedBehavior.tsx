"use client";

import { useEffect } from "react";

const KEY = "prismo:sidebar";

function expandSidebar() {
  document.documentElement.setAttribute("data-sb", "expanded");
  try {
    localStorage.setItem(KEY, "expanded");
  } catch {
    /* ignore */
  }
}

function isCollapsed() {
  return document.documentElement.getAttribute("data-sb") === "collapsed";
}

function isInteractiveTarget(target: EventTarget | null) {
  if (!(target instanceof Element)) return false;
  return Boolean(
    target.closest(
      "a[href], button, input, select, textarea, summary, [role='button'], [data-sidebar-entry='true']",
    ),
  );
}

// 折叠态：入口按钮本身负责导航；点击侧边栏其他空白区域才展开侧边栏。
export function SidebarCollapsedBehavior() {
  useEffect(() => {
    const sidebar = document.querySelector<HTMLElement>(".app-sidebar");
    if (!sidebar) return;

    const handleClick = (event: MouseEvent) => {
      if (!isCollapsed() || isInteractiveTarget(event.target)) return;
      expandSidebar();
    };

    sidebar.addEventListener("click", handleClick);
    return () => sidebar.removeEventListener("click", handleClick);
  }, []);

  return null;
}
