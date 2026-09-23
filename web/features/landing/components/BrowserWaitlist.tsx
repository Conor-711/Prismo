"use client";

import { useEffect, useState } from "react";
import { landingLanguage, type LandingLanguage } from "../browserLanguage";
import type { WaitlistCopy } from "../types";
import { WaitlistForm } from "./WaitlistForm";
import { Brand } from "./Brand";
import { BASE_PATH } from "@/lib/site";
import styles from "../landing.module.css";

export function BrowserWaitlist({ copy }: { copy: Record<LandingLanguage, WaitlistCopy> }) {
  const [lang, setLang] = useState<LandingLanguage>("en");
  useEffect(() => {
    let active = true;
    const update = () => {
      if (!active) return;
      const next = landingLanguage(navigator.languages?.[0] || navigator.language);
      setLang(next);
      document.documentElement.lang = next === "zh" ? "zh-CN" : "en";
    };
    // Run after the legacy route-language provider initializes its document lang.
    queueMicrotask(update);
    window.addEventListener("languagechange", update);
    return () => { active = false; window.removeEventListener("languagechange", update); };
  }, []);

  return <div className={styles.landing} lang={lang === "zh" ? "zh-CN" : "en"}>
    <main className={styles.main} aria-label="bSmart">
      <header className={styles.brandHeader}>
        <img className={styles.cover} src={`${BASE_PATH}/brand/market-editorial-annie-spratt.jpg`} alt="" fetchPriority="high" />
        <div className={styles.brandContent}>
          <Brand />
          <p className={styles.tagline}>{copy[lang].tagline}</p>
        </div>
      </header>
      <section className={styles.application} id="apply" aria-labelledby="application-title">
        <div className={styles.formHeading}>
          <h1 id="application-title">{copy[lang].survey.title}</h1>
          <span>{copy[lang].survey.required}</span>
        </div>
        <WaitlistForm copy={copy[lang]} lang={lang} />
      </section>
    </main>
  </div>;
}
