"use client";

import { useState } from "react";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { GoogleButton } from "./GoogleButton";
import { AppleButton } from "./AppleButton";
import { EmailAuthForm } from "./EmailAuthForm";
import { Divider, Alert } from "./parts";

// 登录/注册的方法面板：主推 Google + Apple（两枚等大按钮）；
// 账密入口默认折叠成一个小药丸按钮，点开才展开邮箱表单。
export function AuthOptions({ mode }: { mode: "login" | "signup" }) {
  const { dict } = useLocale();
  const t = dict.auth;
  const [oauthErr, setOauthErr] = useState("");
  const [showEmail, setShowEmail] = useState(false);

  return (
    <div>
      {oauthErr && (
        <div className="mb-3">
          <Alert kind="error">{oauthErr}</Alert>
        </div>
      )}

      {/* 一键登录：Google + Apple，等高等宽 */}
      <div className="space-y-2.5">
        <GoogleButton onError={setOauthErr} />
        <AppleButton onError={setOauthErr} />
      </div>

      {/* 邮箱：默认折叠为一枚药丸按钮，点开才展开表单 */}
      {!showEmail ? (
        <div className="mt-5 text-center">
          <button
            type="button"
            onClick={() => setShowEmail(true)}
            className="inline-flex items-center gap-2 rounded-full px-4 py-2 text-[13px] font-medium text-neutral-500 ring-1 ring-inset ring-line transition hover:text-reddit hover:ring-reddit/40"
          >
            <MailIcon />
            {mode === "login" ? t.emailLoginToggle : t.emailSignupToggle}
          </button>
        </div>
      ) : (
        <div className="mt-5 space-y-3">
          <Divider>{mode === "login" ? t.orEmailLogin : t.orEmailSignup}</Divider>
          <EmailAuthForm mode={mode} />
          <button
            type="button"
            onClick={() => setShowEmail(false)}
            className="block w-full pt-0.5 text-center text-xs text-neutral-600 transition hover:text-neutral-400"
          >
            {t.collapseEmail}
          </button>
        </div>
      )}
    </div>
  );
}

function MailIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <path d="m3 7 9 6 9-6" />
    </svg>
  );
}
