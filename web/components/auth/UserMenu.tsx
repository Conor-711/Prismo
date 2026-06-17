"use client";

import { useEffect, useRef, useState } from "react";
import { LocaleLink } from "@/components/i18n/LocaleLink";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { useAuth } from "./AuthProvider";
import { displayName, avatarUrl } from "@/lib/auth";

function AvatarBubble({ name, src, size = 30 }: { name: string; src: string | null; size?: number }) {
  if (src) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={src} alt={name} width={size} height={size} className="rounded-full object-cover ring-1 ring-white/10" style={{ width: size, height: size }} referrerPolicy="no-referrer" />;
  }
  return (
    <span
      className="grid place-items-center rounded-full bg-reddit/90 text-white font-semibold ring-1 ring-white/10"
      style={{ width: size, height: size, fontSize: size * 0.42 }}
    >
      {(name.charAt(0) || "U").toUpperCase()}
    </span>
  );
}

export function UserMenu() {
  const { dict } = useLocale();
  const t = dict.auth;
  const p = dict.profile;
  const { user, loading, signOut } = useAuth();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const onDoc = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", onDoc);
    return () => document.removeEventListener("mousedown", onDoc);
  }, []);

  if (loading) return <div className="w-[30px] h-[30px] rounded-full bg-white/5 animate-pulse" />;

  if (!user) {
    return (
      <LocaleLink
        href="/login"
        className="inline-flex items-center gap-1.5 rounded-lg bg-reddit text-white text-sm font-bold px-4 py-2 shadow-lg shadow-reddit/30 ring-1 ring-inset ring-white/15 hover:brightness-110 hover:shadow-reddit/50 transition"
      >
        <svg viewBox="0 0 24 24" className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4M10 17l5-5-5-5M15 12H3" />
        </svg>
        {t.loginLink}
      </LocaleLink>
    );
  }

  const name = displayName(user);
  const avatar = avatarUrl(user);

  return (
    <div className="relative" ref={ref}>
      <button
        onClick={() => setOpen((o) => !o)}
        className="flex items-center gap-2 rounded-lg pl-1 pr-1.5 sm:pr-2 py-1 hover:bg-white/5 transition"
      >
        <AvatarBubble name={name} src={avatar} />
        <span className="hidden sm:block text-sm text-neutral-200 max-w-[120px] truncate">{name}</span>
        <svg viewBox="0 0 24 24" className="hidden sm:block w-4 h-4 text-neutral-500" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M6 9l6 6 6-6" />
        </svg>
      </button>

      {open && (
        <div className="absolute right-0 mt-2 w-56 rounded-xl border border-line bg-elevated shadow-xl shadow-black/40 p-1.5 z-50">
          <div className="px-3 py-2">
            <div className="text-sm font-medium text-cream truncate">{name}</div>
            <div className="text-xs text-neutral-500 truncate">{user.email}</div>
          </div>
          <div className="h-px bg-line my-1" />
          <LocaleLink
            href="/me"
            onClick={() => setOpen(false)}
            className="flex items-center gap-2 px-3 py-2 rounded-lg text-sm text-neutral-300 hover:bg-white/5 hover:text-cream transition"
          >
            <svg viewBox="0 0 24 24" className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M6 4h12a1 1 0 0 1 1 1v15l-7-4-7 4V5a1 1 0 0 1 1-1z" /></svg>
            {p.navTitle}
          </LocaleLink>
          <LocaleLink
            href="/account"
            onClick={() => setOpen(false)}
            className="flex items-center gap-2 px-3 py-2 rounded-lg text-sm text-neutral-300 hover:bg-white/5 hover:text-cream transition"
          >
            <svg viewBox="0 0 24 24" className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth="1.8"><circle cx="12" cy="8" r="4" /><path d="M4 21a8 8 0 0 1 16 0" /></svg>
            {t.accountTitle}
          </LocaleLink>
          <button
            onClick={async () => {
              setOpen(false);
              await signOut();
            }}
            className="w-full flex items-center gap-2 px-3 py-2 rounded-lg text-sm text-bear hover:bg-bear/10 transition"
          >
            <svg viewBox="0 0 24 24" className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" /></svg>
            {t.signOut}
          </button>
        </div>
      )}
    </div>
  );
}
