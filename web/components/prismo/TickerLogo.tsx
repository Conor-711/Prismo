"use client";

import { useState } from "react";
import { tickerLogoUrl } from "@/lib/tickerMeta";

// 标的 logo：第三方 CDN；加载失败回退到青绿字母 tile（所以漏图也好看）。
export function TickerLogo({ ticker, size = 28, className = "" }: { ticker: string; size?: number; className?: string }) {
  const [err, setErr] = useState(false);
  const t = (ticker || "").toUpperCase();

  if (err || !t) {
    return (
      <span
        className={`grid place-items-center shrink-0 rounded-[4px] bg-reddit/15 text-reddit font-display font-bold ${className}`}
        style={{ width: size, height: size, fontSize: Math.round(size * 0.42) }}
        aria-hidden
      >
        {t.charAt(0) || "?"}
      </span>
    );
  }
  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={tickerLogoUrl(t)}
      alt={`${t} logo`}
      width={size}
      height={size}
      onError={() => setErr(true)}
      loading="lazy"
      referrerPolicy="no-referrer"
      className={`shrink-0 rounded-[4px] bg-white object-contain ${className}`}
      style={{ width: size, height: size }}
    />
  );
}
