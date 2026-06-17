"use client";

import { useEffect } from "react";
import { defaultLocale, isLocale } from "@/lib/i18n";

// 根路径无 chrome：按浏览器语言把用户送到 /zh、/en、/ja 或 /ko（默认中文）。
// 静态导出下生成的 index.html 会在加载时用 JS 跳转。
export default function RootRedirect() {
  useEffect(() => {
    // 1) 优先用户上次手动选择（LanguageSwitcher 写入）；
    // 2) 否则按浏览器首选语言顺序匹配支持的语言（zh/ja/ko/en），都不匹配 → en。
    let lang = "";
    try {
      const saved = localStorage.getItem("redditalpha:lang");
      if (saved && isLocale(saved)) lang = saved;
    } catch {
      /* ignore */
    }
    if (!lang) {
      const list =
        typeof navigator !== "undefined"
          ? navigator.languages && navigator.languages.length
            ? navigator.languages
            : [navigator.language || ""]
          : [];
      for (const raw of list) {
        const l = (raw || "").toLowerCase();
        if (l.startsWith("zh")) { lang = "zh"; break; }
        if (l.startsWith("ja")) { lang = "ja"; break; }
        if (l.startsWith("ko")) { lang = "ko"; break; }
        if (l.startsWith("en")) { lang = "en"; break; }
      }
      if (!lang) lang = "en";
    }
    const base = location.pathname.endsWith("/") ? location.pathname : location.pathname + "/";
    location.replace(base + lang + "/");
  }, []);

  return (
    <main style={{ display: "grid", placeItems: "center", minHeight: "70vh", color: "#8A8A99" }}>
      <noscript>
        <a href={`/${defaultLocale}/`} style={{ color: "#FC3E02" }}>
          进入 redditalpha / Enter
        </a>
      </noscript>
      <span style={{ fontFamily: "system-ui", letterSpacing: ".3px" }}>
        reddit<span style={{ color: "#FC3E02" }}>alpha</span> …
      </span>
    </main>
  );
}
