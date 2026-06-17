"use client";

import { useEffect, useRef, useState } from "react";

const BASE = process.env.NEXT_PUBLIC_BASE_PATH || "";

// 真实 subreddit 头像（下载自 Reddit，存 public/communities/{id}.png）。
// 没有自定义头像、或头像加载失败的社区 → 统一回退到 Reddit 官方 logo（橙色 Snoo 标）。
export function CommunityIcon({ id, size = 20, className = "" }: { id: string; size?: number; className?: string }) {
  const [err, setErr] = useState(false);
  const ref = useRef<HTMLImageElement>(null);

  // 关键修复：SSR/静态导出场景下，图片常在 React 挂上 onError 之前就已加载失败，
  // 导致 onError 漏触发、破图一直留在那。挂载时主动检查「已加载完成但宽=0」=失败 → 回退。
  useEffect(() => {
    const img = ref.current;
    if (img && img.complete && img.naturalWidth === 0) setErr(true);
  }, []);

  if (err) {
    return (
      <span
        className={`grid place-items-center rounded-full shrink-0 overflow-hidden bg-elevated ring-1 ring-inset ring-white/10 ${className}`}
        style={{ width: size, height: size }}
        aria-label={`r/${id}`}
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={`${BASE}/reddit_logo.png`} alt="Reddit" className="w-[76%] h-[76%] object-contain" />
      </span>
    );
  }

  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      ref={ref}
      src={`${BASE}/communities/${id}.png`}
      alt={`r/${id}`}
      onError={() => setErr(true)}
      className={`rounded-full object-cover shrink-0 ring-1 ring-black/10 ${className}`}
      style={{ width: size, height: size }}
    />
  );
}
