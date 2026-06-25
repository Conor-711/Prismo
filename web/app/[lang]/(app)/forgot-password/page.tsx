"use client";

import { useState } from "react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { AuthShell } from "@/components/auth/AuthShell";
import { Field, Alert } from "@/components/auth/parts";
import { sendPasswordReset, friendlyError } from "@/lib/auth";

export default function ForgotPasswordPage() {
  const { dict } = useLocale();
  const t = dict.auth;
  const [email, setEmail] = useState("");
  const [err, setErr] = useState("");
  const [msg, setMsg] = useState("");
  const [loading, setLoading] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErr("");
    setMsg("");
    setLoading(true);
    try {
      await sendPasswordReset(email);
      setMsg(t.resetSent.replace("{email}", email));
    } catch (e) {
      setErr(friendlyError(e));
    } finally {
      setLoading(false);
    }
  };

  return (
    <AuthShell
      title={t.resetTitle}
      subtitle={t.resetSubtitle}
      footer={
        <LocaleLink href="/login" className="text-reddit hover:underline">
          {t.backToLogin}
        </LocaleLink>
      }
    >
      <form onSubmit={submit} className="space-y-3">
        {err && <Alert kind="error">{err}</Alert>}
        {msg && <Alert kind="success">{msg}</Alert>}
        <Field label={t.email} type="email" value={email} onChange={setEmail} placeholder="you@example.com" autoComplete="email" required />
        <button
          type="submit"
          disabled={loading}
          className="w-full rounded-lg bg-reddit text-white font-semibold py-2.5 hover:brightness-110 transition disabled:opacity-60"
        >
          {loading ? t.sending : t.sendResetLink}
        </button>
      </form>
    </AuthShell>
  );
}
