"use client";

import { LocaleLink } from "@/components/i18n/LocaleLink";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { AuthShell } from "@/components/auth/AuthShell";
import { AuthOptions } from "@/components/auth/AuthOptions";
import { Alert } from "@/components/auth/parts";
import { useAuth } from "@/components/auth/AuthProvider";

export default function SignupPage() {
  const { dict } = useLocale();
  const t = dict.auth;
  const { configured } = useAuth();
  return (
    <AuthShell
      title={t.signupTitle}
      subtitle={t.signupSubtitle}
      footer={
        <>
          {t.haveAccount}
          <LocaleLink href="/login" className="text-reddit hover:underline font-medium ml-1">
            {t.loginLink}
          </LocaleLink>
        </>
      }
    >
      {!configured && (
        <div className="mb-4">
          <Alert kind="info">{t.notConfiguredSignup}</Alert>
        </div>
      )}
      <AuthOptions mode="signup" />
      <p className="mt-4 text-xs text-neutral-600 text-center leading-relaxed">{t.terms}</p>
    </AuthShell>
  );
}
