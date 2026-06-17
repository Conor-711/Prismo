"use client";

import { useState } from "react";
import { useLocale } from "./i18n/LocaleProvider";
import { track } from "@/lib/analytics";
import { SITE_URL, BASE_PATH } from "@/lib/site";

// 一键分享：把内容页推到 X / Reddit / Telegram / WhatsApp，或复制链接。
// 链接带 utm 便于归因；每次分享记一条 share 事件（管理员看板可见传播效果）。
export function ShareBar({ path, text, ticker }: { path: string; text: string; ticker?: string }) {
  const { lang, dict } = useLocale();
  const t = dict.share;
  const [copied, setCopied] = useState(false);

  const link = (medium: string) =>
    `${SITE_URL}${BASE_PATH}${path}?utm_source=share&utm_medium=${medium}`;
  const enc = encodeURIComponent;

  const share = (platform: string, href: string) => {
    track("share", { lang, ticker, meta: { platform } });
    window.open(href, "_blank", "noopener,noreferrer,width=600,height=560");
  };

  const onCopy = async () => {
    try {
      await navigator.clipboard.writeText(link("copy"));
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
      track("share", { lang, ticker, meta: { platform: "copy" } });
    } catch {
      /* clipboard 不可用时忽略 */
    }
  };

  return (
    <div className="flex flex-wrap items-center gap-1.5">
      <span className="text-[12px] text-neutral-500 mr-0.5">{t.label}</span>

      <Pill label="X" onClick={() => share("x", `https://twitter.com/intent/tweet?text=${enc(text)}&url=${enc(link("x"))}`)}>
        <XIcon />
      </Pill>
      <Pill label="Reddit" onClick={() => share("reddit", `https://www.reddit.com/submit?url=${enc(link("reddit"))}&title=${enc(text)}`)}>
        <RedditIcon />
      </Pill>
      <Pill label="Telegram" onClick={() => share("telegram", `https://t.me/share/url?url=${enc(link("telegram"))}&text=${enc(text)}`)}>
        <TelegramIcon />
      </Pill>
      <Pill label="WhatsApp" onClick={() => share("whatsapp", `https://wa.me/?text=${enc(text + " " + link("whatsapp"))}`)}>
        <WhatsAppIcon />
      </Pill>

      <button
        onClick={onCopy}
        className={`inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-[12px] font-medium ring-1 ring-inset transition ${
          copied ? "text-bull ring-bull/30 bg-bull/10" : "text-neutral-300 ring-line bg-white/[.04] hover:text-cream hover:bg-white/[.07]"
        }`}
      >
        <LinkIcon />
        {copied ? t.copied : t.copy}
      </button>
    </div>
  );
}

function Pill({ label, onClick, children }: { label: string; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      aria-label={label}
      title={label}
      className="grid place-items-center w-8 h-8 rounded-lg text-neutral-300 ring-1 ring-inset ring-line bg-white/[.04] hover:text-cream hover:bg-reddit/15 hover:ring-reddit/30 transition"
    >
      {children}
    </button>
  );
}

/* 简洁单色图标 */
function XIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M18.244 2H21.5l-7.5 8.57L23 22h-6.844l-5.36-7.01L4.66 22H1.4l8.02-9.17L1 2h7.02l4.84 6.4L18.244 2zm-1.2 18h1.9L7.04 4H5.02l12.024 16z" />
    </svg>
  );
}
function RedditIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M22 12.06c0-1.2-.98-2.18-2.18-2.18-.58 0-1.1.22-1.49.59-1.47-1-3.46-1.64-5.66-1.72l.97-4.55 3.16.67a1.56 1.56 0 1 0 .17-.93l-3.53-.75a.39.39 0 0 0-.46.3l-1.08 5.06c-2.24.07-4.26.71-5.75 1.72a2.17 2.17 0 0 0-1.49-.59A2.18 2.18 0 0 0 2 12.06c0 .84.48 1.57 1.18 1.93-.03.2-.05.4-.05.61 0 3.07 3.58 5.56 7.99 5.56s7.99-2.49 7.99-5.56c0-.2-.02-.4-.05-.6.7-.36 1.19-1.1 1.19-1.94zM7.2 13.6a1.3 1.3 0 1 1 2.6 0 1.3 1.3 0 0 1-2.6 0zm7.3 3.45c-.88.88-3.56.9-4.5.9-.94 0-3.62-.02-4.5-.9a.34.34 0 0 1 .48-.48c.55.55 2.74.74 4.02.74 1.28 0 3.47-.19 4.02-.74a.34.34 0 1 1 .48.48zm-.2-2.15a1.3 1.3 0 1 1 0-2.6 1.3 1.3 0 0 1 0 2.6z" />
    </svg>
  );
}
function TelegramIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M21.94 4.3 18.7 19.6c-.24 1.08-.88 1.34-1.78.84l-4.92-3.63-2.37 2.28c-.26.26-.48.48-.99.48l.35-5 9.1-8.22c.4-.35-.09-.55-.62-.2L5.2 13.1.36 11.6c-1.05-.33-1.07-1.05.22-1.55L20.6 2.78c.87-.32 1.64.2 1.34 1.52z" />
    </svg>
  );
}
function WhatsAppIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M12.04 2c-5.5 0-9.96 4.46-9.96 9.96 0 1.76.46 3.45 1.34 4.95L2 22l5.25-1.38a9.9 9.9 0 0 0 4.79 1.22c5.5 0 9.96-4.46 9.96-9.96S17.54 2 12.04 2zm5.8 14.06c-.24.68-1.4 1.3-1.93 1.34-.5.04-.97.22-3.28-.69-2.76-1.09-4.5-3.92-4.64-4.1-.13-.18-1.1-1.47-1.1-2.8 0-1.33.7-1.98.95-2.25.24-.27.53-.34.7-.34l.5.01c.16 0 .38-.06.59.45.24.58.8 2 .87 2.14.07.14.12.31.02.49-.09.18-.14.29-.27.45-.13.16-.28.35-.4.47-.13.13-.27.28-.12.54.16.27.7 1.15 1.5 1.86 1.04.92 1.9 1.2 2.17 1.34.27.13.42.11.58-.07.16-.18.67-.78.85-1.05.18-.27.36-.22.6-.13.25.09 1.57.74 1.84.88.27.13.45.2.52.31.07.11.07.64-.17 1.32z" />
    </svg>
  );
}
function LinkIcon() {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M10 13a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1 1" />
      <path d="M14 11a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1-1" />
    </svg>
  );
}
