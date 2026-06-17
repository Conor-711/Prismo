"use client";

import { useCallback, useEffect, useRef } from "react";
import { usePathname } from "next/navigation";
import { stripLang } from "@/lib/i18n";
import { track } from "@/lib/analytics";

// 路由变化记录 page_view；按页测「互动时长(activeMs) + 点击 + 滚动深度」，离开时发 page_leave。
// 计时口径（贴近 Chartbeat/GA4 注意力测量）：
//   • 仅在前台(visible)累计；切后台立即结算并停表。
//   • 无操作满 IDLE_MS(60s) 视为空闲，停表（前台挂着不动不计），有操作再恢复。
//   • 单段封顶 MAX_DWELL_MS(30min) 防离群值。
type Seg = { path: string; lang: string; activeMs: number; runStart: number; clicks: number; maxScroll: number };

const MAX_DWELL_MS = 30 * 60 * 1000; // 单段活跃时长上限 30 分钟
const IDLE_MS = 60 * 1000; // 无操作 60 秒 → 空闲，停表

export function AnalyticsTracker() {
  const pathname = usePathname();
  const seg = useRef<Seg | null>(null);
  const lastActivity = useRef(0);

  // 把当前运行段结算进 activeMs 并停表（runStart=0）。
  const bank = useCallback(() => {
    const s = seg.current;
    if (s && s.runStart) {
      s.activeMs += Date.now() - s.runStart;
      s.runStart = 0;
    }
  }, []);

  // 恢复计时（仅当存在且当前停表）。
  const resume = useCallback(() => {
    const s = seg.current;
    if (s && !s.runStart) s.runStart = Date.now();
  }, []);

  // 发一段 page_leave（活跃时长封顶），并清零以便后续片段重新累计。
  const emit = useCallback(() => {
    const s = seg.current;
    if (!s) return;
    if (s.runStart) {
      s.activeMs += Date.now() - s.runStart;
      s.runStart = 0;
    }
    const ms = Math.min(s.activeMs, MAX_DWELL_MS);
    if (ms > 500 || s.clicks > 0) {
      track("page_leave", { path: s.path, lang: s.lang, meta: { ms, clicks: s.clicks, maxScroll: s.maxScroll } });
    }
    s.activeMs = 0;
    s.clicks = 0;
  }, []);

  useEffect(() => {
    const markActive = () => {
      lastActivity.current = Date.now();
      resume();
    };
    const onClick = () => {
      markActive();
      if (seg.current && seg.current.runStart) seg.current.clicks++;
    };
    const onScroll = () => {
      markActive();
      const s = seg.current;
      if (!s || !s.runStart) return;
      const doc = document.documentElement;
      const denom = doc.scrollHeight - doc.clientHeight;
      const pct = denom > 0 ? Math.min(100, Math.round((doc.scrollTop / denom) * 100)) : 100;
      if (pct > s.maxScroll) s.maxScroll = pct;
    };
    const onVis = () => {
      if (document.visibilityState === "hidden") emit(); // 切后台/可能离开 → 结算并停表
      else markActive(); // 回到前台 → 重新计时
    };
    const onHide = () => emit();
    // 空闲检测：每 5s 检查，无操作超 IDLE_MS 则停表（前台挂着不动不计时）。
    const idle = window.setInterval(() => {
      const s = seg.current;
      if (s && s.runStart && Date.now() - lastActivity.current > IDLE_MS) bank();
    }, 5000);

    const acts: string[] = ["mousedown", "keydown", "touchstart", "mousemove", "wheel"];
    acts.forEach((e) => document.addEventListener(e, markActive, { passive: true }));
    document.addEventListener("click", onClick, true);
    window.addEventListener("scroll", onScroll, { passive: true });
    document.addEventListener("visibilitychange", onVis);
    window.addEventListener("pagehide", onHide);
    return () => {
      window.clearInterval(idle);
      acts.forEach((e) => document.removeEventListener(e, markActive));
      document.removeEventListener("click", onClick, true);
      window.removeEventListener("scroll", onScroll);
      document.removeEventListener("visibilitychange", onVis);
      window.removeEventListener("pagehide", onHide);
      emit();
    };
  }, [bank, resume, emit]);

  // 路由变化：先结算上一页，再开新页 + page_view（仪表盘自身不统计）。
  useEffect(() => {
    if (!pathname) return;
    const { lang, rest } = stripLang(pathname);
    const path = rest.replace(/\/+$/, "") || "/";
    emit();
    if (path.startsWith("/insights")) { seg.current = null; return; }
    seg.current = { path, lang, activeMs: 0, runStart: Date.now(), clicks: 0, maxScroll: 0 };
    lastActivity.current = Date.now();
    const m = path.match(/\/ticker\/([^/]+)/);
    const sp = new URLSearchParams(window.location.search);
    const src = sp.get("utm_source");
    const meta = src ? { utm_source: src, utm_medium: sp.get("utm_medium") } : undefined;
    track("page_view", {
      path,
      lang,
      ticker: m ? decodeURIComponent(m[1]).toUpperCase() : undefined,
      meta,
    });
  }, [pathname, emit]);

  return null;
}
