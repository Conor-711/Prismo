"use client";

import { useState } from "react";
import { useLocale } from "./i18n/LocaleProvider";
import { track } from "@/lib/analytics";

// 译文 / 原文 切换：中文模式且有译文时，提供一个分段切换按钮——一边中文译文、一边原文。
// 默认显示中文译文（无需看广告）。original / zh 均为已渲染好的 ReactNode（可从服务端组件传入）。
export function TranslateToggle({
  hasZh,
  original,
  zh,
}: {
  hasZh: boolean;
  original: React.ReactNode;
  zh: React.ReactNode;
}) {
  const { lang, dict } = useLocale();
  const t = dict.translate;
  const [showOriginal, setShowOriginal] = useState(false);

  const pick = (original: boolean) => {
    setShowOriginal(original);
    track("translate_toggle", { lang, meta: { mode: original ? "original" : "zh" } });
  };

  // 英文界面或无译文：直接渲染原文，不显示切换。
  if (lang !== "zh" || !hasZh) return <>{original}</>;

  return (
    <div>
      <div className="mb-3 flex items-center gap-2.5">
        <div className="inline-flex items-center rounded-lg bg-white/[.04] ring-1 ring-inset ring-white/[.08] p-0.5 text-[12px] font-semibold">
          <button
            type="button"
            onClick={() => pick(false)}
            aria-pressed={!showOriginal}
            className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md transition ${
              !showOriginal ? "bg-reddit text-white shadow-sm shadow-reddit/30" : "text-neutral-400 hover:text-cream"
            }`}
          >
            <GlobeIcon />
            {t.tabZh}
          </button>
          <button
            type="button"
            onClick={() => pick(true)}
            aria-pressed={showOriginal}
            className={`px-2.5 py-1 rounded-md transition ${
              showOriginal ? "bg-white/10 text-cream shadow-sm" : "text-neutral-400 hover:text-cream"
            }`}
          >
            {t.tabOriginal}
          </button>
        </div>
        <span className="text-[11px] text-neutral-600">{t.poweredBy}</span>
      </div>
      <div>{showOriginal ? original : zh}</div>
    </div>
  );
}

function GlobeIcon() {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden>
      <circle cx="12" cy="12" r="9" />
      <path d="M3 12h18M12 3c2.5 2.5 2.5 15.5 0 18M12 3c-2.5 2.5-2.5 15.5 0 18" />
    </svg>
  );
}
