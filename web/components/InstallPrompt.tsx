"use client";

import { useEffect, useRef, useState } from "react";
import { useLocale } from "./i18n/LocaleProvider";
import { track } from "@/lib/analytics";

// 移动端「存为 App / 加到主屏」提醒 + 教程。
//  • Android/桌面 Chrome：拦截 beforeinstallprompt → 提供原生「安装」按钮。
//  • iOS（无安装 API）：弹出分步教程（分享 → 添加到主屏幕）。
// 关闭后写 localStorage 不再提示；已是独立窗口(已安装)则不显示。桌面端用 BookmarkHint，本组件仅移动端。
const KEY = "redditalpha:a2hs";
const BASE = process.env.NEXT_PUBLIC_BASE_PATH || "";

type BIPEvent = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
};

function isStandalone(): boolean {
  try {
    return (
      (typeof matchMedia !== "undefined" && matchMedia("(display-mode: standalone)").matches) ||
      (navigator as unknown as { standalone?: boolean }).standalone === true
    );
  } catch {
    return false;
  }
}

function detectIOS(): boolean {
  const ua = navigator.userAgent || "";
  return /iPhone|iPad|iPod/i.test(ua) || (/Macintosh/i.test(ua) && (navigator.maxTouchPoints || 0) > 1);
}

export function InstallPrompt() {
  const { dict } = useLocale();
  const t = dict.install;
  const [show, setShow] = useState(false);
  const [guide, setGuide] = useState(false);
  // 安装模式：safari（底部分享）/ chrome（含 Edge：分享→More→Add）/ android / unsupported（Google App 等内置浏览器，无此功能）
  const [mode, setMode] = useState<"safari" | "chrome" | "android" | "unsupported">("android");
  const [canInstall, setCanInstall] = useState(false);
  const [copied, setCopied] = useState(false);
  const deferred = useRef<BIPEvent | null>(null);

  useEffect(() => {
    try {
      if (localStorage.getItem(KEY)) return;
    } catch {
      /* privacy mode */
    }
    if (isStandalone()) return;
    let mobile = false;
    try {
      mobile = matchMedia("(max-width: 1023px)").matches;
    } catch {
      mobile = false;
    }
    if (!mobile) return; // 桌面端交给 BookmarkHint
    const ua = navigator.userAgent || "";
    const isIos = detectIOS();
    // 按浏览器判定「添加到主屏」可行路径：
    //  • Chrome/Edge(CriOS/EdgiOS)：右上角分享 → More → Add to Home Screen
    //  • Google App / App 内置浏览器(GSA/FBAN/微信…)：无此功能 → 引导用 Safari 或 Chrome 打开
    //  • 其余视为 Safari：底部分享 → 添加到主屏幕
    if (isIos) {
      if (/CriOS|EdgiOS/i.test(ua)) setMode("chrome");
      else if (/GSA\/|FxiOS|OPiOS|FBAN|FBAV|MicroMessenger|Instagram|Line\/|QQ\//i.test(ua)) setMode("unsupported");
      else setMode("safari");
    } else {
      setMode("android");
    }

    const onBIP = (e: Event) => {
      e.preventDefault();
      deferred.current = e as BIPEvent;
      setCanInstall(true);
    };
    const onInstalled = () => dismiss(true);
    window.addEventListener("beforeinstallprompt", onBIP);
    window.addEventListener("appinstalled", onInstalled);

    const timer = window.setTimeout(() => {
      setShow(true);
      track("a2hs_shown");
    }, 3500);
    return () => {
      window.clearTimeout(timer);
      window.removeEventListener("beforeinstallprompt", onBIP);
      window.removeEventListener("appinstalled", onInstalled);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 提醒卡显示时，标记 <html data-install>，让浮动主题按钮(theme-fab)临时隐藏，避免遮挡而无法关闭。
  useEffect(() => {
    const el = document.documentElement;
    if (show) el.setAttribute("data-install", "1");
    else el.removeAttribute("data-install");
    return () => el.removeAttribute("data-install");
  }, [show]);

  const dismiss = (persist: boolean) => {
    if (persist) {
      try {
        localStorage.setItem(KEY, "1");
      } catch {
        /* ignore */
      }
    }
    setShow(false);
    setGuide(false);
  };

  const onCta = async () => {
    const e = deferred.current;
    if (e) {
      try {
        await e.prompt();
        const choice = await e.userChoice;
        track("a2hs_prompt", { meta: { outcome: choice.outcome } });
        deferred.current = null;
        setCanInstall(false);
        dismiss(choice.outcome === "accepted");
      } catch {
        setGuide(true);
      }
    } else {
      track("a2hs_guide");
      setGuide(true);
    }
  };

  const copyUrl = async () => {
    try {
      await navigator.clipboard.writeText("https://www.redditalpha.xyz");
      setCopied(true);
      track("a2hs_copy");
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      /* ignore */
    }
  };

  if (!show) return null;

  // 四种模式各自的标题 / 步骤 / 备注（unsupported 走「复制网址 + 用 Safari/Chrome 打开」分支）。
  const guideTitle =
    mode === "android" ? t.androidGuideTitle
    : mode === "safari" ? t.iosGuideTitle
    : mode === "chrome" ? t.iosChromeGuideTitle
    : t.iosUnsupportedTitle;
  const steps =
    mode === "android" ? [t.androidStep1, t.androidStep2, t.androidStep3]
    : mode === "chrome" ? [t.iosChromeStep1, t.iosChromeStep2, t.iosChromeStep3]
    : [t.iosStep1, t.iosStep2, t.iosStep3]; // safari
  const note = mode === "chrome" ? t.iosChromeNote : mode === "safari" ? t.iosSafariNote : "";

  return (
    <>
      {/* 底部提醒卡（移动端，悬于 Tab 栏之上） */}
      <div className="lg:hidden fixed inset-x-0 z-[45] px-3" style={{ bottom: "calc(3.9rem + env(safe-area-inset-bottom))" }}>
        <div
          className="mx-auto max-w-md panel rounded-2xl p-3 pr-9 relative flex items-center gap-3"
          style={{ boxShadow: "inset 0 0 0 1px rgba(252,62,2,.30), 0 14px 36px rgba(0,0,0,.5)" }}
        >
          <button
            onClick={() => dismiss(true)}
            aria-label={t.close}
            className="absolute top-2 right-2 grid place-items-center w-6 h-6 rounded-md text-neutral-500 hover:text-cream hover:bg-white/10 transition"
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.3" strokeLinecap="round" aria-hidden>
              <path d="M6 6l12 12M18 6L6 18" />
            </svg>
          </button>
          <span className="w-10 h-10 rounded-xl overflow-hidden bg-white shrink-0 ring-1 ring-white/10">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={`${BASE}/logo.png`} alt="" className="w-full h-full object-contain" />
          </span>
          <div className="min-w-0 flex-1">
            <div className="font-display font-bold text-cream text-sm leading-tight">{t.title}</div>
            <div className="text-[12px] text-neutral-400 leading-snug mt-0.5">{t.subtitle}</div>
          </div>
          <button
            onClick={onCta}
            className="shrink-0 rounded-lg px-3 py-2 font-display font-bold text-white text-[13px] hover:brightness-110 transition"
            style={{ backgroundImage: "var(--grad-brand)" }}
          >
            {canInstall ? t.installBtn : t.howBtn}
          </button>
        </div>
      </div>

      {/* 教程弹层 */}
      {guide && (
        <div className="fixed inset-0 z-[90] flex items-end sm:items-center justify-center" role="dialog" aria-modal="true">
          <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" onClick={() => setGuide(false)} />
          <div
            className="relative w-full sm:max-w-md panel rounded-t-2xl sm:rounded-2xl p-5"
            style={{ paddingBottom: "calc(1.5rem + env(safe-area-inset-bottom))" }}
          >
            <div className="flex items-center gap-2 mb-4">
              <PhoneIcon />
              <h3 className="font-display font-extrabold text-cream text-[17px]">{guideTitle}</h3>
            </div>
            {mode === "unsupported" ? (
              <>
                <p className="text-[13.5px] text-neutral-200 leading-relaxed">{t.iosUnsupportedMsg}</p>
                <button
                  onClick={copyUrl}
                  className="mt-4 w-full rounded-xl py-2.5 font-display font-bold text-cream text-sm ring-1 ring-inset ring-line bg-white/[.05] hover:bg-white/[.08] transition"
                >
                  {copied ? t.copied : t.copyBtn}
                </button>
              </>
            ) : (
              <>
                <ol className="space-y-3.5">
                  {steps.map((s, i) => (
                    <li key={i} className="flex items-start gap-3">
                      <span className="shrink-0 grid place-items-center w-6 h-6 rounded-full bg-reddit/15 text-reddit text-[12px] font-bold ring-1 ring-inset ring-reddit/30">
                        {i + 1}
                      </span>
                      <span className="text-[13.5px] text-neutral-200 leading-relaxed">
                        {s}
                        {(mode === "safari" || mode === "chrome") && i === 0 && <ShareIcon />}
                      </span>
                    </li>
                  ))}
                </ol>
                {note && <p className="mt-4 text-[11px] text-neutral-500 leading-relaxed">{note}</p>}
              </>
            )}
            <button
              onClick={() => dismiss(true)}
              className="mt-5 w-full rounded-xl py-2.5 font-display font-bold text-white text-sm hover:brightness-110 transition"
              style={{ backgroundImage: "var(--grad-brand)" }}
            >
              {t.gotIt}
            </button>
          </div>
        </div>
      )}
    </>
  );
}

// iOS 系统「分享」图标（方框 + 上箭头），帮用户认出按钮
function ShareIcon() {
  return (
    <svg viewBox="0 0 24 24" className="inline-block w-4 h-4 mx-1 -mt-0.5 align-middle text-reddit" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M12 15V3M8 7l4-4 4 4" />
      <path d="M5 12v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6" />
    </svg>
  );
}

function PhoneIcon() {
  return (
    <svg viewBox="0 0 24 24" className="w-5 h-5 text-reddit" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <rect x="6" y="2" width="12" height="20" rx="3" />
      <path d="M11 18h2" />
    </svg>
  );
}
