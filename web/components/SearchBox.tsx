"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { IconSearch } from "./icons";
import { useLocale } from "./i18n/LocaleProvider";
import { withLang } from "@/lib/i18n";

export function SearchBox() {
  const router = useRouter();
  const { lang, dict } = useLocale();
  const [v, setV] = useState("");
  const go = (e: React.FormEvent) => {
    e.preventDefault();
    const t = v.trim().toUpperCase();
    if (t) router.push(withLang(lang, `/ticker/${encodeURIComponent(t)}`));
  };
  return (
    <form onSubmit={go} className="relative hidden sm:block">
      <IconSearch className="w-4 h-4 absolute left-2.5 top-1/2 -translate-y-1/2 text-neutral-500" />
      <input
        value={v}
        onChange={(e) => setV(e.target.value)}
        placeholder={dict.chrome.searchPlaceholder}
        className="w-44 lg:w-56 bg-ink/60 border border-line rounded-lg pl-8 pr-3 py-1.5 text-sm text-neutral-200 placeholder:text-neutral-600 focus:outline-none focus:border-amber/50 focus:ring-2 focus:ring-amber/15"
      />
    </form>
  );
}
