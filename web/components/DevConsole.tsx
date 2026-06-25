"use client";

// 测试/开发控制台（隐藏页 /[lang]/lab/dev）：一组按钮，点一下就能触发/重置各功能来自测。
// 仅操作「当前登录用户自己的」数据（RLS 保护），无破坏性风险。文案故意只用中文（内部工具，不进多语字典）。
import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Panel } from "@/components/ui";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { withLang } from "@/lib/i18n";
import { useAuth } from "@/components/auth/AuthProvider";
import { useFavorites } from "@/components/favorites/FavoritesProvider";
import { isAdminEmail } from "@/lib/admin";
import { isTrackingDisabled, setTrackingDisabled } from "@/lib/analytics";
import {
  loadProfile,
  clearProfile,
  resetOnboarding,
  isOnboarded,
  type UserProfile,
} from "@/lib/profile";

// 与各模块约定一致的 localStorage key（仅测试重置用）
const A2HS_KEY = "prismo:a2hs";
const ANALYTICS_KEYS = ["prismo:vid", "prismo:fseen"]; // localStorage
const ANALYTICS_SESSION_KEYS = ["prismo:sid", "prismo:sstart"]; // sessionStorage

export function DevConsole() {
  const { lang } = useLocale();
  const router = useRouter();
  const { user, loading, signOut } = useAuth();
  const fav = useFavorites();

  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [busy, setBusy] = useState<string>("");
  const [flash, setFlash] = useState<string>("");
  const [trackingOff, setTrackingOff] = useState(false);
  const [standalone, setStandalone] = useState(false);

  const refresh = useCallback(async () => {
    if (user) setProfile(await loadProfile(user.id));
    setTrackingOff(isTrackingDisabled());
    if (typeof window !== "undefined") {
      setStandalone(window.matchMedia?.("(display-mode: standalone)").matches || (navigator as unknown as { standalone?: boolean }).standalone === true);
    }
  }, [user]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const note = (m: string) => {
    setFlash(m);
    setTimeout(() => setFlash(""), 2200);
  };

  const run = async (key: string, fn: () => Promise<void> | void, msg?: string) => {
    setBusy(key);
    try {
      await fn();
      if (msg) note(msg);
      await refresh();
    } finally {
      setBusy("");
    }
  };

  const go = (path: string) => router.push(withLang(lang, path));

  if (loading) return <div className="py-24 text-center text-sm text-neutral-500">···</div>;

  if (!user) {
    return (
      <Shell>
        <Panel className="p-5 text-sm text-neutral-400">
          需要登录后才能测试账号相关功能。
          <button onClick={() => go("/login")} className="ml-2 text-reddit hover:underline">
            去登录 →
          </button>
        </Panel>
      </Shell>
    );
  }

  const onb = isOnboarded(user);
  const admin = isAdminEmail(user.email);

  return (
    <Shell>
      {flash && (
        <div className="sticky top-2 z-10 rounded-lg bg-bull/15 text-bull text-sm px-3 py-2 ring-1 ring-inset ring-bull/30">
          {flash}
        </div>
      )}

      {/* 登录态 */}
      <Section title="登录态">
        <KV k="邮箱" v={user.email || "—"} />
        <KV k="UID" v={user.id} mono />
        <KV k="登录方式" v={(user.app_metadata?.provider as string) || "email"} />
        <KV k="管理员" v={admin ? "是（门禁不强推引导）" : "否"} />
        <KV k="已完成引导(onboarded)" v={onb ? "true" : "false"} />
        <Row>
          <Btn onClick={() => run("signout", async () => { await signOut(); go("/login"); })} busy={busy === "signout"} tone="danger">
            登出
          </Btn>
        </Row>
      </Section>

      {/* Onboarding —— 本次重点 */}
      <Section title="Onboarding 引导流程">
        <Row>
          <Btn onClick={() => run("re", () => resetOnboarding(user.id).then(() => go("/onboarding")))} busy={busy === "re"} tone="primary">
            重走引导（保留画像）
          </Btn>
          <Btn
            onClick={() => run("reclear", async () => { await clearProfile(user.id); await resetOnboarding(user.id); go("/onboarding"); })}
            busy={busy === "reclear"}
            tone="primary"
          >
            重置并重走（清空画像）
          </Btn>
          <Btn onClick={() => go("/onboarding?edit=1")} tone="ghost">
            打开编辑模式
          </Btn>
        </Row>
        <Row>
          <Btn onClick={() => run("clear", async () => { await clearProfile(user.id); }, "画像已清空")} busy={busy === "clear"} tone="ghost">
            仅清空画像（不跳转）
          </Btn>
          <Btn
            onClick={() => run("resetflag", () => resetOnboarding(user.id), "已重置 onboarded 标志（停留本页，刷新或换页时门禁会引导）")}
            busy={busy === "resetflag"}
            tone="ghost"
          >
            仅重置 onboarded 标志
          </Btn>
          <Btn onClick={() => run("refresh", refresh)} busy={busy === "refresh"} tone="ghost">
            刷新读取画像
          </Btn>
        </Row>
        <pre className="mt-2 max-h-56 overflow-auto rounded-lg bg-ink/70 ring-1 ring-inset ring-line p-3 text-[11px] leading-relaxed text-neutral-400">
          {JSON.stringify(profile ?? { 提示: "暂无画像行（未填或已清空）" }, null, 2)}
        </pre>
      </Section>

      {/* 收藏 / 追踪 */}
      <Section title="收藏 / 追踪（user_collections）">
        <div className="grid grid-cols-3 sm:grid-cols-5 gap-2">
          {(["post", "comment", "subreddit", "ticker", "author"] as const).map((k) => (
            <div key={k} className="rounded-lg bg-card ring-1 ring-inset ring-line px-3 py-2 text-center">
              <div className="font-display text-lg font-extrabold text-cream tabular">{fav.countOf(k)}</div>
              <div className="text-[11px] text-neutral-500">{k}</div>
            </div>
          ))}
        </div>
        <Row>
          <Btn onClick={() => go("/me")} tone="ghost">
            打开个人主页 /me
          </Btn>
        </Row>
      </Section>

      {/* 埋点 / Analytics */}
      <Section title="埋点 / Analytics">
        <KV k="本设备不记录(DNT)" v={trackingOff ? "true（已排除自有访问）" : "false"} />
        <Row>
          <Btn onClick={() => run("dnt", () => { setTrackingDisabled(!trackingOff); })} busy={busy === "dnt"} tone="primary">
            {trackingOff ? "恢复记录本设备" : "标记本设备不记录"}
          </Btn>
          <Btn
            onClick={() =>
              run("vid", () => {
                try {
                  ANALYTICS_KEYS.forEach((k) => localStorage.removeItem(k));
                  ANALYTICS_SESSION_KEYS.forEach((k) => sessionStorage.removeItem(k));
                } catch {/* ignore */}
              }, "已重置访客身份（vid/会话）；刷新后按新访客记录")
            }
            busy={busy === "vid"}
            tone="ghost"
          >
            重置访客身份（vid/会话）
          </Btn>
          <Btn onClick={() => go("/insights")} tone="ghost">
            打开数据看板 /insights
          </Btn>
        </Row>
      </Section>

      {/* PWA / 安装 */}
      <Section title="PWA / 安装">
        <KV k="已作为 App 运行(standalone)" v={standalone ? "true" : "false"} />
        <Row>
          <Btn
            onClick={() => run("a2hs", () => { try { localStorage.removeItem(A2HS_KEY); } catch {/* ignore */} }, "已重置安装提示；刷新页面后会重新出现")}
            busy={busy === "a2hs"}
            tone="ghost"
          >
            重置「存为 App」提示
          </Btn>
        </Row>
      </Section>

      <p className="text-[11px] text-neutral-600 leading-relaxed">
        本页仅作自测：所有操作只影响你自己（当前登录用户）的数据，受 Supabase RLS 保护。隐藏页、noindex、不进导航与 sitemap，URL 直达。
      </p>
    </Shell>
  );
}

/* ---------- 布局小件 ---------- */

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <div className="max-w-2xl mx-auto space-y-4">
      <header>
        <h1 className="font-display font-extrabold text-cream text-2xl tracking-tight">测试控制台</h1>
        <p className="mt-1 text-sm text-neutral-500">点按钮即时触发/重置各功能来自测（onboarding、收藏、埋点、PWA…）。</p>
      </header>
      {children}
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <Panel className="p-5 space-y-3">
      <div className="flex items-center gap-2">
        <span className="w-[3px] h-3.5 rounded-full bg-reddit shrink-0" />
        <h2 className="font-display text-[13px] font-bold text-cream tracking-tight">{title}</h2>
      </div>
      {children}
    </Panel>
  );
}

function Row({ children }: { children: React.ReactNode }) {
  return <div className="flex flex-wrap gap-2">{children}</div>;
}

function KV({ k, v, mono = false }: { k: string; v: string; mono?: boolean }) {
  return (
    <div className="flex items-baseline gap-3 text-sm">
      <span className="w-44 shrink-0 text-neutral-500">{k}</span>
      <span className={`min-w-0 break-all text-neutral-200 ${mono ? "font-display" : ""}`}>{v}</span>
    </div>
  );
}

function Btn({
  children,
  onClick,
  busy = false,
  tone = "ghost",
}: {
  children: React.ReactNode;
  onClick: () => void;
  busy?: boolean;
  tone?: "primary" | "ghost" | "danger";
}) {
  const cls =
    tone === "primary"
      ? "bg-reddit text-white hover:brightness-110"
      : tone === "danger"
      ? "border border-bear/30 text-bear hover:bg-bear/10"
      : "bg-card text-neutral-300 ring-1 ring-inset ring-line hover:ring-reddit/40 hover:text-cream";
  return (
    <button
      onClick={onClick}
      disabled={busy}
      className={`rounded-lg px-3.5 py-2 text-sm font-medium transition disabled:opacity-60 ${cls}`}
    >
      {busy ? "…" : children}
    </button>
  );
}
