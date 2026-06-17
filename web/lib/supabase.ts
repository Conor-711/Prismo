import { createClient, type SupabaseClient } from "@supabase/supabase-js";

// 公开变量（anon key 可安全暴露在前端）。缺失时 isAuthConfigured=false，
// 整站照常构建/运行，只是 auth 动作会提示"未配置"，不会崩。
const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

export const isAuthConfigured = Boolean(url && anon);

export const supabase: SupabaseClient | null = isAuthConfigured
  ? createClient(url as string, anon as string, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true, // 自动处理 OAuth / 邮件链接回调
        flowType: "pkce",
      },
    })
  : null;

export const AUTH_NOT_CONFIGURED =
  "账号系统尚未配置：请在 web/.env.local 填入 Supabase 的 URL 与 anon key（见 SUPABASE_AUTH.md）。";
