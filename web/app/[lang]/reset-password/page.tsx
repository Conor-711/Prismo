"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { withLang } from "@/lib/i18n";
import { AuthShell } from "@/components/auth/AuthShell";
import { Field, Alert } from "@/components/auth/parts";
import { updatePassword, friendlyError } from "@/lib/auth";

export default function ResetPasswordPage() {
  const { lang, dict } = useLocale();
  const t = dict.auth;
  const router = useRouter();
  const [pw, setPw] = useState("");
  const [pw2, setPw2] = useState("");
  const [err, setErr] = useState("");
  const [done, setDone] = useState(false);
  const [loading, setLoading] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErr("");
    if (pw !== pw2) {
      setErr(t.pwMismatch);
      return;
    }
    setLoading(true);
    try {
      await updatePassword(pw);
      setDone(true);
      setTimeout(() => router.push(withLang(lang, "/")), 1500);
    } catch (e) {
      setErr(friendlyError(e));
      setLoading(false);
    }
  };

  return (
    <AuthShell title={t.setNewTitle} subtitle={t.setNewSubtitle}>
      {done ? (
        <Alert kind="success">{t.pwUpdatedRedirect}</Alert>
      ) : (
        <form onSubmit={submit} className="space-y-3">
          {err && <Alert kind="error">{err}</Alert>}
          <Field label={t.newPassword} type="password" value={pw} onChange={setPw} placeholder={t.pwMin} autoComplete="new-password" required minLength={6} />
          <Field label={t.confirmNewPassword} type="password" value={pw2} onChange={setPw2} placeholder={t.pwAgain} autoComplete="new-password" required minLength={6} />
          <button
            type="submit"
            disabled={loading}
            className="w-full rounded-lg bg-reddit text-white font-semibold py-2.5 hover:brightness-110 transition disabled:opacity-60"
          >
            {loading ? t.updating : t.updatePassword}
          </button>
        </form>
      )}
    </AuthShell>
  );
}
