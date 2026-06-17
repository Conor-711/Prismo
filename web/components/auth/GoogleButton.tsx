"use client";

import { useState } from "react";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { signInWithGoogle, friendlyError } from "@/lib/auth";
import { GoogleLogo } from "./parts";

export function GoogleButton({ onError }: { onError?: (m: string) => void }) {
  const { dict } = useLocale();
  const t = dict.auth;
  const [loading, setLoading] = useState(false);
  const go = async () => {
    setLoading(true);
    try {
      await signInWithGoogle(); // 成功则跳转到 Google
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
      className="w-full inline-flex h-[52px] items-center justify-center gap-3 rounded-xl bg-white text-[15px] font-semibold text-[#1f1f1f] ring-1 ring-black/10 shadow-sm transition hover:-translate-y-px hover:bg-neutral-50 hover:shadow-md active:translate-y-0 disabled:opacity-60"
    >
      <GoogleLogo />
      {loading ? t.googleRedirecting : t.googleContinue}
    </button>
  );
}
