import type { User } from "@supabase/supabase-js";
import { supabase, AUTH_NOT_CONFIGURED } from "./supabase";

// 回调/重定向 URL（兼容 basePath 与 trailingSlash）。仅在浏览器调用。
// 站点所有页面都在 /[lang] 下（zh/en）；auth/callback、reset-password 是静态导出页，
// 必须带语言前缀——否则像 /auth/callback/ 这种无前缀路径在静态站上 404。
function appRedirect(path: string): string {
  const base = process.env.NEXT_PUBLIC_BASE_PATH || "";
  const origin = typeof window !== "undefined" ? window.location.origin : "";
  const seg = typeof window !== "undefined" ? window.location.pathname.split("/")[1] : "";
  const lang = seg === "en" ? "en" : "zh"; // 取当前路径的语言前缀，默认 zh
  return `${origin}${base}/${lang}${path}`;
}

export async function signInWithEmail(email: string, password: string) {
  if (!supabase) throw new Error(AUTH_NOT_CONFIGURED);
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data;
}

export async function signUpWithEmail(email: string, password: string) {
  if (!supabase) throw new Error(AUTH_NOT_CONFIGURED);
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: { emailRedirectTo: appRedirect("/auth/callback/") },
  });
  if (error) throw error;
  return data; // data.session === null → 需邮箱确认（走验证码 OTP）
}

// 验证「注册确认」6 位验证码（OTP）。成功返回含 session 的 data → 即已登录。
export async function verifyEmailOtp(email: string, token: string) {
  if (!supabase) throw new Error(AUTH_NOT_CONFIGURED);
  const { data, error } = await supabase.auth.verifyOtp({ email, token: token.trim(), type: "signup" });
  if (error) throw error;
  return data;
}

// 重发注册验证码（同一封「Confirm signup」邮件，模板含 {{ .Token }} 时即为 6 位码）。
export async function resendSignupCode(email: string) {
  if (!supabase) throw new Error(AUTH_NOT_CONFIGURED);
  const { error } = await supabase.auth.resend({ type: "signup", email });
  if (error) throw error;
}

export async function signInWithGoogle() {
  if (!supabase) throw new Error(AUTH_NOT_CONFIGURED);
  const { error } = await supabase.auth.signInWithOAuth({
    provider: "google",
    options: { redirectTo: appRedirect("/auth/callback/") },
  });
  if (error) throw error; // 成功则浏览器跳转到 Google
}

export async function signInWithApple() {
  if (!supabase) throw new Error(AUTH_NOT_CONFIGURED);
  const { error } = await supabase.auth.signInWithOAuth({
    provider: "apple",
    options: { redirectTo: appRedirect("/auth/callback/") },
  });
  if (error) throw error; // 成功则浏览器跳转到 Apple
}

export async function signOut() {
  if (supabase) await supabase.auth.signOut();
}

export async function sendPasswordReset(email: string) {
  if (!supabase) throw new Error(AUTH_NOT_CONFIGURED);
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: appRedirect("/reset-password/"),
  });
  if (error) throw error;
}

export async function updatePassword(newPassword: string) {
  if (!supabase) throw new Error(AUTH_NOT_CONFIGURED);
  const { error } = await supabase.auth.updateUser({ password: newPassword });
  if (error) throw error;
}

// ---------- 展示助手 ----------
export function displayName(user: User | null): string {
  if (!user) return "";
  const m = (user.user_metadata || {}) as Record<string, string>;
  return m.full_name || m.name || m.user_name || (user.email ? user.email.split("@")[0] : "用户");
}

export function avatarUrl(user: User | null): string | null {
  if (!user) return null;
  const m = (user.user_metadata || {}) as Record<string, string>;
  return m.avatar_url || m.picture || null;
}

export function friendlyError(e: unknown): string {
  const msg = (e as { message?: string })?.message || String(e);
  const map: Record<string, string> = {
    "Invalid login credentials": "邮箱或密码不正确。",
    "User already registered": "该邮箱已注册，请直接登录。",
    "Email not confirmed": "邮箱尚未验证，请先查收确认邮件。",
    "Password should be at least 6 characters": "密码至少 6 位。",
    "Unable to validate email address: invalid format": "邮箱格式不正确。",
    "For security purposes, you can only request this after 60 seconds.": "操作过于频繁，请 60 秒后再试。",
    "Token has expired or is invalid": "验证码不正确或已过期，请重新获取。",
    "Email link is invalid or has expired": "验证码不正确或已过期，请重新获取。",
    "Invalid token": "验证码不正确。",
    "Signups not allowed for otp": "该邮箱尚未注册，请先创建账号。",
  };
  return map[msg] || msg;
}
