# 账号系统配置（Supabase Auth）

redditalpha 是**静态站点**，账号系统用 **Supabase Auth**（客户端 SDK）实现，支持 **Google**、**Apple** 与**邮箱密码**注册/登录。登录页主推 Google（大按钮）+ Apple，邮箱入口默认折叠成小按钮、点开才展开。本文是一次性配置步骤（约 10 分钟）。

> 不配也能跑：缺少环境变量时，登录/注册页会提示"未配置"，站点其余部分照常工作。

## 1. 建 Supabase 项目
1. 打开 https://supabase.com → 新建 project（免费层即可）。
2. 左下 **Project Settings → API**，复制：
   - **Project URL**（形如 `https://abcd.supabase.co`）
   - **anon public** key
3. 在 `web/` 下新建 `web/.env.local`（已被 git 忽略）：
   ```bash
   cp web/.env.local.example web/.env.local
   ```
   填入：
   ```
   NEXT_PUBLIC_SUPABASE_URL=https://abcd.supabase.co
   NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOi...
   ```
   > anon key 是**公开可暴露**的前端 key，放前端是安全的。

## 2. 开启邮箱登录 + 验证码注册（OTP，非链接）
**Authentication → Providers → Email**：默认已开。**保持 Confirm email 开启**。

前端注册已改为「填邮箱+密码 → 邮件收到 6 位验证码 → 输入验证码」两步（见
`web/components/auth/EmailAuthForm.tsx`，用 `supabase.auth.verifyOtp({type:'signup'})` 校验）。
**要让邮件里出现验证码（而不是链接），必须改邮件模板**：

**Authentication → Email Templates → Confirm signup**，把正文改成包含 `{{ .Token }}`，例如：
```html
<h2>确认注册 redditalpha</h2>
<p>你的验证码：</p>
<p style="font-size:28px;font-weight:bold;letter-spacing:6px">{{ .Token }}</p>
<p>回到注册页输入此验证码完成注册（1 小时内有效）。</p>
```
> 不改模板：邮件仍是旧的确认**链接**，注册页等不到验证码。
> 想完全免验证、注册即登录：关闭 **Confirm email**（则不发验证码、`signUp` 直接返回 session）。

（登录仍是邮箱+密码，不变；验证码只用于注册确认。）

## 3. 配置 Google 登录
### 3a. Google Cloud 创建 OAuth 凭证
1. https://console.cloud.google.com → 新建/选择项目。
2. **APIs & Services → OAuth consent screen**：External，填应用名/邮箱，保存。
3. **APIs & Services → Credentials → Create Credentials → OAuth client ID**：
   - 类型选 **Web application**。
   - **Authorized redirect URIs** 填 Supabase 的回调（**注意是 supabase.co，不是你的站点**）：
     ```
     https://<你的project-ref>.supabase.co/auth/v1/callback
     ```
   - 创建后得到 **Client ID** 与 **Client Secret**。
### 3b. 填回 Supabase
**Authentication → Providers → Google**：开启，粘贴 Client ID 与 Client Secret，保存。

## 3.5 配置 Apple 登录（需 Apple Developer 付费账号）
> Apple 比 Google 麻烦些，且要 99 美元/年的开发者账号。**没有就先只用 Google**——前端 Apple 按钮在 provider 未开时点了会提示登录失败，不影响其它登录方式。

### 3.5a Apple Developer 创建凭证（https://developer.apple.com）
1. **Certificates, IDs & Profiles → Identifiers**：
   - 建一个 **App ID**（或用已有的）。
   - 再建一个 **Services ID**（这就是 OAuth 的 client_id，形如 `com.yourname.web`）。编辑它，勾选 **Sign in with Apple**，配置：
     - **Domains**：`<你的project-ref>.supabase.co`
     - **Return URLs**：`https://<你的project-ref>.supabase.co/auth/v1/callback`
2. **Keys → 新建 Key**，勾选 **Sign in with Apple**，下载 `.p8` 私钥（**只能下一次**），记下 **Key ID** 和你的 **Team ID**。
### 3.5b 填回 Supabase
**Authentication → Providers → Apple**：开启，填 **Services ID**（client_id）、**Team ID**、**Key ID**、`.p8` 私钥内容。保存。

## 4. 设置站点与回调白名单
**Authentication → URL Configuration**：
- **Site URL**：你的站点根地址。
  - 本地开发：`http://localhost:3000`
  - 本地静态部署(`make serve`)：`http://localhost:8080`
  - 线上：你的域名
- **Redirect URLs**（加入下面这些，**注意末尾斜杠**，因为站点开了 trailingSlash）：
  ```
  http://localhost:3000/auth/callback/
  http://localhost:3000/reset-password/
  http://localhost:8080/auth/callback/
  http://localhost:8080/reset-password/
  https://你的域名/auth/callback/
  https://你的域名/reset-password/
  ```
  （部署到 GitHub Pages 项目页等子路径时，URL 要带上 basePath，如 `https://用户名.github.io/reddit_alpha/auth/callback/`，并在 `web/.env.local` 设 `NEXT_PUBLIC_BASE_PATH=/reddit_alpha`。）

## 5. 运行
- 开发：`make web-dev` → http://localhost:3000 ，右上角点「登录」。
- 静态部署：改完 `.env.local` 后重新 `make site`（产物 `web/out/`），再 `make serve`。
  > 环境变量在**构建期**注入前端，改了 env 必须重新 build。

## 功能清单
- `/login`、`/signup`：Google / Apple 一键（主推）+ 邮箱密码（折叠入口）；`/forgot-password`、`/reset-password`：邮件重置；`/account`：资料/改密/登出；`/auth/callback`：OAuth 回调。
- 顶栏用户菜单（头像/邮箱/登出），全局会话由 `AuthProvider` 维护。
- `/me`（个人主页·私密）：帖子/评论收藏、社区/标的/作者追踪；全站卡片上的书签/「追踪」按钮由 `FavoritesProvider` + `SaveButton` 驱动。
  数据存 Supabase 的 `user_collections`（RLS 仅本人可读写）。**需先在 SQL Editor 执行迁移
  `supabase/migrations/20260612000007_user_collections.sql`**，否则收藏/追踪会静默写入失败。

## 说明
- 密码哈希、会话、令牌刷新均由 Supabase 处理；静态站点用客户端会话（localStorage）。
- 用户数据存在 Supabase 的 Postgres（`auth.users`），与项目"生产用 Postgres"的方向一致。
- 当前**数据看板是公开的**（不强制登录）；如需"登录才可见"，可在页面加客户端门禁（已具备 `useAuth` 与 `/account` 的门禁范式）。
