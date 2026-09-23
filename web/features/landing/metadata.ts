import type { Metadata } from "next";
import { getDictionary } from "@/lib/i18n";
import { BASE_PATH, SITE_URL } from "@/lib/site";

export function landingMetadata(lang: string, root = false): Metadata {
  const copy = getDictionary(lang).betaLanding;
  const title = "bSmart";
  const description = copy.tagline;
  const url = `${SITE_URL}${BASE_PATH}${root ? "/" : `/${lang}/`}`;
  return {
    title, description,
    alternates: { canonical: url, languages: { "zh-CN": `${SITE_URL}${BASE_PATH}/`, en: `${SITE_URL}${BASE_PATH}/en/`, "x-default": `${SITE_URL}${BASE_PATH}/` } },
    openGraph: { type: "website", siteName: "bSmart", title, description, url, locale: lang === "zh" ? "zh_CN" : "en_US", images: [{ url: `${SITE_URL}${BASE_PATH}/brand/bsmart-wordmark-beta.png`, width: 1254, height: 1254, alt: "bSmart" }] },
    twitter: { card: "summary", title, description, images: [`${SITE_URL}${BASE_PATH}/brand/bsmart-wordmark-beta.png`] },
  };
}
