"use client";

import { useState } from "react";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { signInWithApple, friendlyError } from "@/lib/auth";
import { AppleLogo } from "./parts";

export function AppleButton({ onError }: { onError?: (m: string) => void }) {
  const { dict } = useLocale();
  const t = dict.auth;
  const [loading, setLoading] = useState(false);
  const go = async () => {
    setLoading(true);
    try {
      await signInWithApple(); // 成功则跳转到 Apple
    } catch (e) {
      onError?.(friendlyError(e));
      setLoading(false);
    }
  };
  return (
    <button
      type="button"
      onClick={go}
      disabled={loading}
      className="w-full inline-flex h-[52px] items-center justify-center gap-3 rounded-xl bg-black text-[15px] font-semibold text-white ring-1 ring-white/10 shadow-sm transition hover:-translate-y-px hover:bg-neutral-900 hover:shadow-md active:translate-y-0 disabled:opacity-60"
    >
      <AppleLogo />
      {loading ? t.appleRedirecting : t.appleContinue}
    </button>
  );
}
