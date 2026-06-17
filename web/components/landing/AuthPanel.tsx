"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/components/auth/AuthProvider";
import { GoogleButton } from "@/components/auth/GoogleButton";
import { AppleButton } from "@/components/auth/AppleButton";
import { EmailAuthForm } from "@/components/auth/EmailAuthForm";
import { IconArrow } from "@/components/icons";
import { setGuest, clearOnboarding } from "@/lib/onboarding";

export function AuthPanel() {
  const { configured } = useAuth();
  const router = useRouter();
  const [emailOpen, setEmailOpen] = useState(false);
  const [mode, setMode] = useState<"login" | "signup">("login");
  const [oauthErr, setOauthErr] = useState("");

  const enterAsGuest = () => {
    setGuest(true);
    clearOnboarding(); // 每次游客登录都重新走一遍引导（测试用）
    router.push("/onboarding");
  };

  return (
    <div className="space-y-3.5">
      {/* —— 主操作：游客登录 —— */}
      <button
        type="button"
        onClick={enterAsGuest}
        className="group relative w-full overflow-hidden rounded-xl px-5 py-4 ring-1 ring-inset ring-white/15 shadow-lg shadow-reddit/30 transition hover:-translate-y-px hover:shadow-reddit/40 active:translate-y-0"
        style={{ backgroundImage: "var(--grad-brand)" }}
      >
        <span
          className="pointer-events-none absolute inset-0 -translate-x-full transition-transform duration-[900ms] ease-out group-hover:translate-x-full"
          style={{ background: "linear-gradient(100deg, transparent 35%, rgba(255,255,255,0.28) 50%, transparent 65%)" }}
        />
        <span className="relative inline-flex items-center justify-center gap-2 font-display font-bold text-white text-[15px]">
          游客登录 · 立即体验
          <IconArrow className="w-4 h-4 transition group-hover:translate-x-0.5" />
        </span>
      </button>
      <p className="text-center text-[12px] text-neutral-500">无需注册 · 立即体验完整的个性化引导</p>

      {/* —— 分隔 —— */}
      <Divider>或使用账号登录</Divider>

      {/* —— Google / Apple —— */}
      <GoogleButton onError={setOauthErr} />
      <AppleButton onError={setOauthErr} />
      {oauthErr && <p className="text-center text-xs text-bear">{oauthErr}</p>}

      {/* —— 邮箱：默认折叠，点开再展开 —— */}
      {!emailOpen ? (
        <button
          type="button"
          onClick={() => setEmailOpen(true)}
          className="w-full inline-flex items-center justify-center gap-2 rounded-xl px-5 py-3 text-sm font-medium text-neutral-300 bg-white/[.02] ring-1 ring-inset ring-white/10 hover:ring-white/20 hover:text-cream transition"
        >
          <MailIcon /> 用邮箱登录或注册
        </button>
      ) : (
        <div className="rounded-xl bg-ink/40 ring-1 ring-inset ring-white/[.07] p-4">
          <div className="flex p-1 rounded-lg bg-white/[.03] ring-1 ring-inset ring-white/[.06] mb-3.5">
            <Seg active={mode === "login"} onClick={() => setMode("login")}>
              登录
            </Seg>
            <Seg active={mode === "signup"} onClick={() => setMode("signup")}>
              注册
            </Seg>
          </div>
          <EmailAuthForm mode={mode} />
          <button
            type="button"
            onClick={() => setEmailOpen(false)}
            className="mt-3 w-full text-center text-xs text-neutral-600 hover:text-neutral-400 transition"
          >
            收起
          </button>
        </div>
      )}

      {!configured && (
        <p className="text-center text-[11px] text-neutral-600 pt-0.5">
          邮箱 / Google 登录即将开放 · 现在用<span className="text-neutral-500">游客</span>体验
        </p>
      )}
    </div>
  );
}

function Divider({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-3 py-0.5">
      <span className="h-px flex-1 bg-gradient-to-r from-transparent to-line" />
      <span className="text-[10px] font-semibold uppercase tracking-[0.14em] text-neutral-600 whitespace-nowrap">
        {children}
      </span>
      <span className="h-px flex-1 bg-gradient-to-l from-transparent to-line" />
    </div>
  );
}

function Seg({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`flex-1 rounded-md py-1.5 text-sm font-medium transition ${
        active ? "bg-white/[.08] text-cream shadow-sm shadow-black/20" : "text-neutral-500 hover:text-neutral-300"
      }`}
    >
      {children}
    </button>
  );
}

function MailIcon() {
  return (
    <svg viewBox="0 0 24 24" className="w-4 h-4 text-neutral-500" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <path d="m3 7 9 6 9-6" />
    </svg>
  );
}
