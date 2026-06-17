"use client";

import Link from "next/link";
import { withLang } from "@/lib/i18n";
import { useLocale } from "./LocaleProvider";

type LinkProps = React.ComponentProps<typeof Link>;

// 与 next/link 同接口，但自动给内部字符串 href 加上当前语言前缀。
// 外链 / 锚点 / mailto / UrlObject 不处理。
export function LocaleLink({ href, ...rest }: LinkProps) {
  const { lang } = useLocale();
  const h = typeof href === "string" ? withLang(lang, href) : href;
  return <Link href={h} {...rest} />;
}
