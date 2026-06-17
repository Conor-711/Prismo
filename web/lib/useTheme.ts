"use client";

import { useEffect, useState } from "react";

// 给 canvas 图表(ECharts)用：读取当前是否白天模式，并随主题切换实时更新。
// 默认 = 白天(无 .dark 类)；夜间 = html.dark。
export function useIsLight(): boolean {
  const [dark, setDark] = useState(false);
  useEffect(() => {
    const el = document.documentElement;
    const sync = () => setDark(el.classList.contains("dark"));
    sync();
    const obs = new MutationObserver(sync);
    obs.observe(el, { attributes: true, attributeFilter: ["class"] });
    return () => obs.disconnect();
  }, []);
  return !dark;
}
