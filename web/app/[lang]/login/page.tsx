"use client";

import { LocaleLink } from "@/components/i18n/LocaleLink";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { AuthShell } from "@/components/auth/AuthShell";
import { AuthOptions } from "@/components/auth/AuthOptions";
import { Alert } from "@/components/auth/parts";
import { useAuth } from "@/components/auth/AuthProvider";

export default function LoginPage() {
  const { dict } = useLocale();
  const t = dict.auth;
  const { configured } = useAuth();
  return (
    <AuthShell
      title={t.loginTitle}
      subtitle={t.loginSubtitle}
      footer={
        <>
          {t.noAccount}
          <LocaleLink href="/signup" className="text-reddit hover:underline font-medium ml-1">
            {t.signupLink}
          </LocaleLink>
        </>
      }
    >
      {!configured && (
        <div className="mb-4">
          <Alert kind="info">{t.notConfiguredLogin}</Alert>
        </div>
      )}
      <AuthOptions mode="login" />
    </AuthShell>
  );
}
