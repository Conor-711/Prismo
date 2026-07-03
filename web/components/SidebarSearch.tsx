"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { IconSearch } from "./icons";
import { useLocale } from "./i18n/LocaleProvider";
import { withLang } from "@/lib/i18n";

export function SidebarSearch() {
  const router = useRouter();
  const { lang, dict } = useLocale();
  const [value, setValue] = useState("");

  useEffect(() => {
    router.prefetch(withLang(lang, "/search"));
  }, [lang, router]);

  const go = () => {
    const q = value.trim().toUpperCase();
    if (!q) {
      router.push(withLang(lang, "/search"));
      return;
    }
    router.push(withLang(lang, `/tickers/${encodeURIComponent(q)}`));
  };

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    go();
  };

  const activateCollapsedSearch = (event: React.MouseEvent<HTMLFormElement>) => {
    if (document.documentElement.getAttribute("data-sb") !== "collapsed") return;
    if (event.target instanceof HTMLInputElement) return;
    event.preventDefault();
    go();
  };

  return (
    <form onSubmit={submit} onClick={activateCollapsedSearch} data-sidebar-entry="true" className="sb-search-form group relative mx-3 mb-2 flex h-9 items-center rounded-lg bg-white/[.035] px-2.5 text-neutral-500 ring-1 ring-inset ring-line transition hover:bg-white/[.055] hover:text-neutral-200 focus-within:text-reddit focus-within:ring-reddit/55">
      <button type="submit" aria-label={dict.nav.search} className="sb-search-submit grid h-5 w-5 shrink-0 place-items-center">
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
