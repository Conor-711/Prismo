// 管理员判定（前端仅作 UI 显隐 / 自动免追踪用；真正的访问控制在 Supabase 端）：
// 数据看板的聚合函数内用 is_admin() 校验 JWT 邮箱（查 app_admins 名单表），
// 非管理员即便绕过前端也读不到任何数据。
//
// 多管理员：NEXT_PUBLIC_ADMIN_EMAIL 支持逗号分隔多个邮箱；下面的默认值兜底。
// 新增管理员请同时在迁移 app_admins 表里 INSERT 一行（否则能看到看板但拿不到数据）。
const DEFAULT_ADMINS = ["admin@redditalpha.xyz", "analytics@redditalpha.xyz"];

export const ADMIN_EMAILS: string[] = Array.from(
  new Set(
    [...(process.env.NEXT_PUBLIC_ADMIN_EMAIL || "").split(","), ...DEFAULT_ADMINS]
      .map((e) => e.trim().toLowerCase())
      .filter(Boolean),
  ),
);

// 向后兼容：旧代码引用的单数 ADMIN_EMAIL = 第一个管理员。
export const ADMIN_EMAIL = ADMIN_EMAILS[0];

export function isAdminEmail(email?: string | null): boolean {
  return !!email && ADMIN_EMAILS.includes(email.trim().toLowerCase());
}
