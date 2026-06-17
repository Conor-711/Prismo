"use client";

// 顶部公告横幅：宣传「账号系统上线」，引导访客注册去收藏帖子 / 作者 / 社区。
// 展示条件：后端已配置 + 未登录（登录态加载完成前不闪现）。
// 关闭 ×：只隐藏「本次浏览」；刷新后会重新出现，直到用户真正登录（user 存在则永久不显示）。
import { useState } from "react";
import { LocaleLink } from "./i18n/LocaleLink";
import { useLocale } from "./i18n/LocaleProvider";
import { useAuth } from "./auth/AuthProvider";

export function TopBanner() {
  const { dict } = useLocale();
  const t = dict.banner;
  const { user, loading, configured } = useAuth();
  const [dismissed, setDismissed] = useState(false);

  if (!configured || loading || user || dismissed) return null;

  return (
    <div className="text-white bg-gradient-to-r from-reddit via-[#FF5A1F] to-[#FF7A2A]">
      <div className="flex items-center gap-2.5 sm:gap-3 px-4 sm:px-6 lg:px-8 py-2.5">
        <span className="shrink-0 inline-flex items-center rounded-full bg-white/20 px-2 py-0.5 text-[11px] font-bold tracking-wide ring-1 ring-inset ring-white/30">
          {t.tag}
        </span>
        <p className="min-w-0 truncate text-[13px] sm:text-sm leading-snug">
          <span className="font-bold">{t.title}</span>
          <span className="hidden sm:inline text-white/90"> · {t.desc}</span>
        </p>
        {/* 紧贴文案右侧；不再钉在最右边（最右边留给 × 关闭，避免误触/难点） */}
        <LocaleLink
          href="/signup"
          className="shrink-0 inline-flex items-center gap-1 rounded-full bg-white text-reddit text-xs sm:text-[13px] font-bold px-3.5 py-1.5 shadow-sm hover:bg-white/90 transition"
        >
          {t.cta} →
        </LocaleLink>
        <button
          onClick={() => setDismissed(true)}
          aria-label={t.close}
          className="shrink-0 ml-auto grid place-items-center w-7 h-7 rounded-md text-white/80 hover:text-white hover:bg-white/15 transition"
        >
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" aria-hidden>
            <path d="M6 6l12 12M18 6L6 18" />
          </svg>
        </button>
      </div>
    </div>
  );
}
