"use client";

// 首登门禁：已登录但未完成引导的「普通用户」→ 自动送去 /onboarding。
// 只读 session 里的 user_metadata.onboarded（isOnboarded，无 DB IO）。无 UI。
// 排除：未配置 / 加载中 / 管理员（站长免打扰）/ 已在 auth·onboarding 相关页。
import { useEffect } from "react";
import { usePathname, useRouter } from "next/navigation";
import { useAuth } from "@/components/auth/AuthProvider";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { isAdminEmail } from "@/lib/admin";
import { isOnboarded } from "@/lib/profile";
import { withLang } from "@/lib/i18n";

// /[lang]/ 之后的首段在这些里时不拦（避免把人从登录/引导流程里弹走）
const EXCLUDED_SEGMENTS = new Set(["onboarding", "login", "signup", "forgot-password", "reset-password", "auth"]);

export function OnboardingGate() {
  const { user, loading, configured } = useAuth();
  const { lang } = useLocale();
  const router = useRouter();
  const pathname = usePathname() || "/";

  useEffect(() => {
    if (loading || !configured || !user) return;
    if (isOnboarded(user) || isAdminEmail(user.email)) return;
    const seg = pathname.split("/").filter(Boolean)[1] || ""; // [lang, seg, ...]
    if (EXCLUDED_SEGMENTS.has(seg)) return;
    router.replace(withLang(lang, "/onboarding"));
  }, [user, loading, configured, pathname, lang, router]);

  return null;
}
