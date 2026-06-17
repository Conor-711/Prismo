"use client";

import { useEffect } from "react";
import { track } from "@/lib/analytics";

const BASE = process.env.NEXT_PUBLIC_BASE_PATH || "";

// 注册 Service Worker（PWA 可安装 + 离线壳）。本地/内网跳过，避免开发期缓存困扰。
// 另外记录 appinstalled（Android/桌面 Chrome「安装」时触发）→ 统计「把站点存为 App」的用户数。
export function PwaRegister() {
  useEffect(() => {
    if (typeof navigator === "undefined" || !("serviceWorker" in navigator)) return;
    const h = location.hostname;
    if (h === "localhost" || h === "127.0.0.1" || h === "::1" || !h.includes(".")) return;
    const onLoad = () => {
      navigator.serviceWorker.register(`${BASE}/sw.js`).catch(() => {});
    };
    if (document.readyState === "complete") onLoad();
    else window.addEventListener("load", onLoad, { once: true });

    const onInstalled = () => track("pwa_install");
    window.addEventListener("appinstalled", onInstalled);
    return () => window.removeEventListener("appinstalled", onInstalled);
  }, []);
  return null;
}
