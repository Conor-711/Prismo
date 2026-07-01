"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { IconSearch } from "./icons";
import { useLocale } from "./i18n/LocaleProvider";
import { withLang } from "@/lib/i18n";

export function SidebarSearch() {
  const router = useRouter();
  const { lang, dict } = useLocale();
  const [value, setValue] = useState("");

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    const q = value.trim().toUpperCase();
    if (!q) {
      router.push(withLang(lang, "/search"));
      return;
    }
    router.push(withLang(lang, `/tickers/${encodeURIComponent(q)}`));
  };

  return (
    <form onSubmit={submit} className="sb-search-form group relative mx-3 mb-2 flex h-9 items-center rounded-lg bg-white/[.035] px-2.5 text-neutral-500 ring-1 ring-inset ring-line transition hover:bg-white/[.055] hover:text-neutral-200 focus-within:text-reddit focus-within:ring-reddit/55">
      <button type="submit" aria-label={dict.nav.search} className="grid h-5 w-5 shrink-0 place-items-center">
        <IconSearch className="h-[17px] w-[17px]" />
      </button>
      <input
        value={value}
        onChange={(event) => setValue(event.target.value)}
        placeholder={dict.chrome.searchPlaceholder}
        className="sb-search-input ml-2 min-w-0 flex-1 bg-transparent text-[13px] font-medium text-cream outline-none placeholder:text-neutral-600"
      />
    </form>
  );
}
