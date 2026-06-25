"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { withLang } from "@/lib/i18n";
import { AuthShell } from "@/components/auth/AuthShell";
import { Alert } from "@/components/auth/parts";

export default function AuthCallbackPage() {
  const { lang, dict } = useLocale();
  const t = dict.auth;
  const router = useRouter();
  const [err, setErr] = useState("");

  useEffect(() => {
    if (!supabase) {
      router.replace(withLang(lang, "/login"));
      return;
    }
    // URL 中可能带 OAuth 错误
    const hash = typeof window !== "undefined" ? window.location.hash : "";
    if (hash.includes("error")) {
      const p = new URLSearchParams(hash.slice(1));
      setErr(p.get("error_description") || t.callbackOauthFailed);
      return;
    }

    let tries = 0;
    let alive = true;
    const check = async () => {
      const { data } = await supabase!.auth.getSession();
      if (!alive) return;
      if (data.session) {
        router.replace(withLang(lang, "/"));
      } else if (tries++ < 25) {
        setTimeout(check, 200);
      } else {
        setErr(t.callbackTimeout);
      }
    };
    check();

    const { data: sub } = supabase.auth.onAuthStateChange((_e, session) => {
      if (session) router.replace(withLang(lang, "/"));
    });
    return () => {
      alive = false;
      sub.subscription.unsubscribe();
    };
  }, [router, lang, t.callbackOauthFailed, t.callbackTimeout]);

  return (
    <AuthShell title={err ? t.callbackLoginFailed : t.callbackLoggingIn} subtitle={err ? undefined : t.callbackVerifying}>
      {err ? (
        <>
          <Alert kind="error">{err}</Alert>
          <div className="mt-4 text-center">
            <LocaleLink href="/login" className="text-reddit text-sm hover:underline">
              {t.backToLogin}
            </LocaleLink>
          </div>
        </>
      ) : (
        <div className="flex justify-center py-3">
          <svg className="animate-spin w-7 h-7 text-reddit" viewBox="0 0 24 24" fill="none">
            <circle className="opacity-20" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="3" />
            <path className="opacity-90" d="M22 12a10 10 0 0 1-10 10" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
          </svg>
        </div>
      )}
    </AuthShell>
  );
}
