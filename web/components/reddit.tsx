// Reddit 视觉元素（用官方素材，放在 public/）：
// - SnooAvatar：4 张官方风格 Reddit 头像之一(按用户名稳定取)，圆形 + 品牌色圆底 = 用户头像
// - RedditMark：官方 Reddit logo（橙色对话泡 + Snoo）= 品牌标记
// - SnooMascot：线稿 Snoo（含身体），用于空状态 / 水印等
import { subColor } from "@/lib/format";

const BASE = process.env.NEXT_PUBLIC_BASE_PATH || "";

// public/avatars 下的 4 张 Reddit 头像，按用户名哈希稳定分配
const AVATARS = ["/avatars/snoo-1.png", "/avatars/snoo-2.png", "/avatars/snoo-3.png", "/avatars/snoo-4.png"];
function nameHash(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return Math.abs(h);
}

export function SnooAvatar({ name, size = 20 }: { name: string; size?: number }) {
  const key = name || "?";
  const bg = subColor(key);
  const src = AVATARS[nameHash(key) % AVATARS.length];
  return (
    <span
      className="inline-grid place-items-center rounded-full shrink-0 overflow-hidden ring-1 ring-black/10"
      style={{ width: size, height: size, background: bg }}
      aria-hidden
    >
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={`${BASE}${src}`} alt="" className="w-full h-full object-cover object-top" />
    </span>
  );
}

export function RedditMark({ size = 20 }: { size?: number }) {
  return (
    <span className="inline-grid place-items-center shrink-0" style={{ width: size, height: size }} aria-hidden>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={`${BASE}/reddit_logo.png`} alt="Reddit" className="w-full h-full object-contain" />
    </span>
  );
}

// 完整身体的 Reddit 头像角色，用作页面吉祥物（落地页 / 今日Alpha 头牌 / 空状态等）。
export function SnooCharacter({ n = 1, className = "" }: { n?: 1 | 2 | 3 | 4 | "a" | "b" | "c"; className?: string }) {
  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={`${BASE}/avatars/snoo-${n}.png`}
      alt=""
      aria-hidden
      className={`select-none pointer-events-none ${className}`}
    />
  );
}

export function SnooMascot({ className = "w-12 h-14" }: { className?: string }) {
  return (
    <svg viewBox="0 0 64 80" className={className} fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      {/* 天线 */}
      <path d="M32 16V5" />
      <circle cx="32" cy="3.5" r="2.8" fill="currentColor" stroke="none" />
      {/* 头 */}
      <ellipse cx="32" cy="34" rx="20" ry="18" />
      {/* 眼 */}
      <circle cx="25" cy="33" r="3.1" fill="currentColor" stroke="none" />
      <circle cx="39" cy="33" r="3.1" fill="currentColor" stroke="none" />
      {/* 嘴 */}
      <path d="M26 42 Q32 47 38 42" strokeWidth="2.4" />
      {/* 身体 */}
      <path d="M18 52 Q18 71 32 71 Q46 71 46 52" />
    </svg>
  );
}
