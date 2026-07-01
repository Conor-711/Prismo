"use client";

import { LocaleLink } from "@/components/i18n/LocaleLink";
import { useLocale } from "@/components/i18n/LocaleProvider";
import { useAuth } from "./AuthProvider";
import { avatarUrl, displayName } from "@/lib/auth";

function AccountIcon({ name, src }: { name: string; src: string | null }) {
  if (src) {
    return (
      // eslint-disable-next-line @next/next/no-img-element
      <img
        src={src}
        alt={name}
        className="h-[26px] w-[26px] shrink-0 rounded-full object-cover ring-1 ring-white/10"
        referrerPolicy="no-referrer"
      />
    );
  }
  return (
    <span className="grid h-[26px] w-[26px] shrink-0 place-items-center rounded-full bg-reddit/90 text-[12px] font-semibold text-white ring-1 ring-white/10">
      {(name.charAt(0) || "U").toUpperCase()}
    </span>
  );
}

export function SidebarAccount() {
  const { dict } = useLocale();
  const { user, loading } = useAuth();

  if (loading) {
    return <div className="h-10 rounded-lg bg-white/[.04] animate-pulse" />;
  }

  if (!user) {
    return (
      <LocaleLink
        href="/login"
        title={dict.auth.loginLink}
        className="sb-row flex items-center gap-3 rounded-lg px-3 py-2 text-[13.5px] font-semibold text-neutral-300 transition hover:bg-white/[.05] hover:text-cream"
      >
        <span className="grid h-[26px] w-[26px] shrink-0 place-items-center rounded-lg bg-reddit/15 text-reddit ring-1 ring-inset ring-reddit/30">
          <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="2.1" strokeLinecap="round" strokeLinejoin="round">
            <path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4M10 17l5-5-5-5M15 12H3" />
          </svg>
        </span>
        <span className="sb-label">{dict.auth.loginLink}</span>
      </LocaleLink>
    );
  }

  const name = displayName(user);
  const avatar = avatarUrl(user);

  return (
    <LocaleLink
      href="/account"
      title={name}
      className="sb-row flex items-center gap-3 rounded-lg px-3 py-2 text-[13.5px] font-semibold text-neutral-300 transition hover:bg-white/[.05] hover:text-cream"
    >
      <AccountIcon name={name} src={avatar} />
      <span className="sb-label min-w-0 flex-1 truncate">{name}</span>
    </LocaleLink>
  );
}
