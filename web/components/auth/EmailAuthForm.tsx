"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { withLang } from "@/lib/i18n";
import { signInWithEmail, signUpWithEmail, verifyEmailOtp, resendSignupCode, friendlyError } from "@/lib/auth";
import { Field, Alert } from "./parts";

export function EmailAuthForm({ mode }: { mode: "login" | "signup" }) {
  const { lang, dict } = useLocale();
  const t = dict.auth;
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [pw, setPw] = useState("");
  const [code, setCode] = useState("");
  const [step, setStep] = useState<"form" | "code">("form");
  const [err, setErr] = useState("");
  const [msg, setMsg] = useState("");
  const [loading, setLoading] = useState(false);

  const toDashboard = () => router.push(withLang(lang, "/dashboard"));

  // 第一步：登录 or 注册（注册成功且需确认 → 进入验证码步骤）
  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErr("");
    setMsg("");
    setLoading(true);
    try {
      if (mode === "login") {
        await signInWithEmail(email, pw);
        toDashboard(); // 跳转后由 AuthProvider 更新状态
      } else {
        const data = await signUpWithEmail(email, pw);
        if (data.session) {
          toDashboard(); // 未开启邮箱确认 → 直接登录
        } else {
          setStep("code"); // 需验证码确认
          setMsg(t.codeSent.replace("{email}", email));
          setLoading(false);
        }
      }
    } catch (e) {
      setErr(friendlyError(e));
      setLoading(false);
    }
  };

  // 第二步：输入 6 位验证码完成注册
  const submitCode = async (e: React.FormEvent) => {
    e.preventDefault();
    setErr("");
    setLoading(true);
    try {
      const data = await verifyEmailOtp(email, code);
      if (data.session) {
        toDashboard();
      } else {
        setErr(friendlyError("Invalid token"));
        setLoading(false);
      }
    } catch (e) {
      setErr(friendlyError(e));
      setLoading(false);
    }
  };

  const resend = async () => {
    setErr("");
    setMsg("");
    try {
      await resendSignupCode(email);
      setMsg(t.resent);
    } catch (e) {
      setErr(friendlyError(e));
    }
  };

  // ===== 验证码步骤（仅注册）=====
  if (step === "code") {
    return (
      <form onSubmit={submitCode} className="space-y-3">
        {err && <Alert kind="error">{err}</Alert>}
        {msg && <Alert kind="success">{msg}</Alert>}
        <p className="text-sm text-neutral-400 leading-relaxed">{t.codeHint}</p>
        <Field
          label={t.codeLabel}
          type="text"
          value={code}
          onChange={(v) => setCode(v.replace(/\D/g, "").slice(0, 6))}
          placeholder={t.codePlaceholder}
          autoComplete="one-time-code"
          required
        />
        <button
          type="submit"
          disabled={loading || code.length < 6}
          className="btn-grad w-full text-cream font-semibold py-2.5 disabled:opacity-60"
        >
          {loading ? t.verifying : t.verifyBtn}
        </button>
        <div className="flex items-center justify-between pt-1">
          <button
            type="button"
            onClick={() => {
              setStep("form");
              setErr("");
              setMsg("");
              setCode("");
              setLoading(false);
            }}
            className="text-xs text-neutral-500 hover:text-reddit transition"
          >
            {t.changeEmail}
          </button>
          <button type="button" onClick={resend} className="text-xs text-neutral-500 hover:text-reddit transition">
            {t.resendCode}
          </button>
        </div>
      </form>
    );
  }

  // ===== 表单步骤（登录 / 注册）=====
  return (
    <form onSubmit={submit} className="space-y-3">
      {err && <Alert kind="error">{err}</Alert>}
      {msg && <Alert kind="success">{msg}</Alert>}
      <Field label={t.email} type="email" value={email} onChange={setEmail} placeholder="you@example.com" autoComplete="email" required />
      <Field
        label={t.password}
        type="password"
        value={pw}
        onChange={setPw}
        placeholder={t.pwMin}
        autoComplete={mode === "login" ? "current-password" : "new-password"}
        required
        minLength={6}
      />
      {mode === "login" && (
        <div className="text-right -mt-1">
          <LocaleLink href="/forgot-password" className="text-xs text-neutral-500 hover:text-reddit transition">
            {t.forgot}
          </LocaleLink>
        </div>
      )}
      <button
        type="submit"
        disabled={loading}
        className="w-full rounded-lg bg-reddit text-white font-semibold py-2.5 hover:brightness-110 transition disabled:opacity-60"
      >
        {loading ? t.processing : mode === "login" ? t.loginBtn : t.createBtn}
      </button>
    </form>
  );
}
