"use client";

import { useEffect, useState } from "react";
import { BASE_PATH } from "@/lib/site";
import { landingLanguage, type LandingLanguage } from "../browserLanguage";
import type { WaitlistCopy } from "../types";
import { Arrow, Brand } from "./Brand";
import { WaitlistForm } from "./WaitlistForm";
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

  const c = copy[lang];
  const s = c.site;
  const screens = [
    { src: "product-investor.jpg", title: s.investorTitle, description: s.investorDescription },
    { src: "product-market.jpg", title: s.marketTitle, description: s.marketDescription },
    { src: "product-updates.jpg", title: s.updatesTitle, description: s.updatesDescription },
  ];
  // Cloudflare's email obfuscation rewrites React-owned HTML and breaks hydration.
  const emailLink = `<!--email_off--><a href="mailto:zfy3712z@gmail.com">${s.footerEmail}: zfy3712z@gmail.com</a><!--/email_off-->`;

  return <div className={styles.landing} lang={lang === "zh" ? "zh-CN" : "en"}>
    <header className={styles.siteHeader}>
      <a className={styles.headerBrand} href="#top" aria-label="bSmart"><Brand /></a>
      <nav className={styles.headerNav} aria-label="Main">
        <a href="#product">{s.productNav}</a>
        <a className={styles.headerAccess} href="#apply">{s.accessNav}<Arrow diagonal /></a>
      </nav>
    </header>
    <main id="top" className={styles.main}>
      <section className={styles.hero} aria-labelledby="hero-title">
        <div className={styles.heroCopy}>
          <span className={styles.heroEyebrow}><span aria-hidden="true" />{s.beta}</span>
          <h1 id="hero-title">{s.heroTitle}</h1>
          <p>{s.heroDescription}</p>
          <div className={styles.heroAction}>
            <a className={styles.heroButton} href="#apply"><span>{s.heroCTA}</span><Arrow /></a>
            <span>{s.heroHint}</span>
          </div>
        </div>
        <div className={styles.heroScreens} aria-hidden="true">
          {screens.map(screen => <img key={screen.src} src={`${BASE_PATH}/brand/${screen.src}`} width="1179" height="2556" alt="" decoding="async" />)}
        </div>
      </section>
      <section className={styles.product} id="product" aria-labelledby="product-title">
        <div className={styles.productHeading}>
          <span className={styles.sectionEyebrow}>{s.productEyebrow}</span>
          <h2 id="product-title">{s.productTitle}</h2>
          <p>{s.productDescription}</p>
        </div>
        <div className={styles.productStage}>
          <div className={styles.productGrid}>
            {screens.map((screen, index) => <article className={styles.productItem} key={screen.src}>
              <div className={styles.productCopy}>
                <span className={styles.productNumber}>0{index + 1} / 03</span>
                <h3>{screen.title}</h3>
                <p>{screen.description}</p>
              </div>
              <div className={styles.productVisual}>
                <img src={`${BASE_PATH}/brand/${screen.src}`} width="1179" height="2556" loading="lazy" decoding="async" alt={`${screen.title} - bSmart`} />
              </div>
            </article>)}
          </div>
        </div>
      </section>
      <section className={styles.application} id="apply" aria-labelledby="application-title">
        <div className={styles.applicationInner}>
          <div className={styles.applicationPitch}>
            <span className={styles.sectionEyebrow}>{s.beta}</span>
            <h2 id="application-title">{c.survey.title}</h2>
            <p>{s.formIntro}</p>
            <div className={styles.applicationPreview} aria-hidden="true">
              <img src={`${BASE_PATH}/brand/product-market.jpg`} width="1179" height="2556" loading="lazy" decoding="async" alt="" />
            </div>
          </div>
          <div className={styles.applicationPanel}>
            <div className={styles.formHeading}>
              <span>{s.formPanelTitle}</span>
              <span>{c.survey.required}</span>
            </div>
            <WaitlistForm copy={c} lang={lang} />
          </div>
        </div>
      </section>
    </main>
    <footer className={styles.footer}>
      <div className={styles.footerInner}>
        <Brand />
        <div className={styles.footerContact}>
          <span>{s.footerContact}</span>
          <span dangerouslySetInnerHTML={{ __html: emailLink }} />
          <a href="https://x.com/try_bSmart" target="_blank" rel="noopener noreferrer">{s.footerX}: x.com/try_bSmart<Arrow diagonal /></a>
        </div>
      </div>
    </footer>
  </div>;
}
