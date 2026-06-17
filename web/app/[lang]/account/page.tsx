"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Panel } from "@/components/ui";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { withLang } from "@/lib/i18n";
import { Field, Alert } from "@/components/auth/parts";
import { useAuth } from "@/components/auth/AuthProvider";
import { updatePassword, friendlyError, displayName, avatarUrl } from "@/lib/auth";

export default function AccountPage() {
  const { lang, dict } = useLocale();
  const t = dict.auth;
  const { user, loading, signOut } = useAuth();
  const router = useRouter();
  const [pw, setPw] = useState("");
  const [err, setErr] = useState("");
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!loading && !user) router.replace(withLang(lang, "/login"));
  }, [loading, user, router, lang]);

  if (loading || !user) {
    return <div className="py-24 text-center text-sm text-neutral-500">{t.loading}</div>;
  }

  const name = displayName(user);
  const avatar = avatarUrl(user);
  const provider = (user.app_metadata?.provider as string) || "email";
  const providerLabel = provider === "google" ? "Google" : t.methodEmail;

  const changePw = async (e: React.FormEvent) => {
    e.preventDefault();
    setErr("");
    setMsg("");
    setBusy(true);
    try {
      await updatePassword(pw);
      setMsg(t.pwUpdated);
      setPw("");
    } catch (e) {
      setErr(friendlyError(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="max-w-2xl mx-auto space-y-4">
      <h1 className="font-display font-extrabold text-cream text-2xl">{t.accountTitle}</h1>

      <Panel className="p-5 flex items-center gap-4">
        {avatar ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={avatar} alt={name} className="w-14 h-14 rounded-full object-cover ring-1 ring-white/10" referrerPolicy="no-referrer" />
        ) : (
          <span className="grid place-items-center w-14 h-14 rounded-full bg-reddit/90 text-white text-xl font-bold ring-1 ring-white/10">
            {(name.charAt(0) || "U").toUpperCase()}
          </span>
        )}
        <div className="min-w-0">
          <div className="font-display font-bold text-cream text-lg truncate">{name}</div>
          <div className="text-sm text-neutral-500 truncate">{user.email}</div>
          <div className="mt-1 inline-flex items-center gap-1.5 text-[11px] px-2 py-0.5 rounded-md bg-white/5 text-neutral-400 ring-1 ring-inset ring-white/8">
            {t.loginMethod}{providerLabel}
          </div>
        </div>
      </Panel>

      {provider === "email" && (
        <Panel className="p-5">
          <h2 className="font-display font-bold text-cream mb-3">{t.changePassword}</h2>
          <form onSubmit={changePw} className="space-y-3 max-w-sm">
            {err && <Alert kind="error">{err}</Alert>}
            {msg && <Alert kind="success">{msg}</Alert>}
            <Field label={t.newPassword} type="password" value={pw} onChange={setPw} placeholder={t.pwMin} autoComplete="new-password" required minLength={6} />
            <button
              type="submit"
              disabled={busy}
              className="rounded-lg bg-reddit text-white font-semibold px-4 py-2 hover:brightness-110 transition disabled:opacity-60"
            >
              {busy ? t.updating : t.updatePassword}
            </button>
          </form>
        </Panel>
      )}

      <Panel className="p-5 flex items-center justify-between">
        <div>
          <div className="font-medium text-cream">{t.signOut}</div>
          <div className="text-sm text-neutral-500">{t.signOutDesc}</div>
        </div>
        <button
          onClick={async () => {
            await signOut();
            router.push(withLang(lang, "/"));
          }}
          className="rounded-lg border border-bear/30 text-bear font-semibold px-4 py-2 hover:bg-bear/10 transition"
        >
          {t.signOut}
        </button>
      </Panel>
    </div>
  );
}
