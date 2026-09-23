"use client";

import { useId, useState } from "react";
import type { LandingCopy } from "../types";
import { Avatar, SourceIcon } from "./ProductScenes";
import styles from "../landing.module.css";

export function ActivityDemo({ copy: c }: { copy: LandingCopy }) {
  const [tab, setTab] = useState(0);
  const id = useId();
  const items = tab === 0
    ? [{ ticker: "NVDA", person: c.researcher, quote: c.demoOpinion1, source: "x" as const, letter: "A" }, { ticker: "AAPL", person: c.researcherB, quote: c.demoOpinion2, source: "youtube" as const, letter: "B" }]
    : [{ ticker: "NVDA", person: c.researcher, quote: c.demoOpinion1, source: "x" as const, letter: "A" }, { ticker: "MSFT", person: c.researcher, quote: c.demoOpinion3, source: "reddit" as const, letter: "A" }];
  return <div className={styles.activityDemo}>
    <div className={styles.demoTop}><span>{c.demo}</span><span className={styles.tinyDot} /></div>
    <div className={styles.demoTabs} role="tablist" aria-label={c.following}>
      {[c.assetTab, c.peopleTab].map((label, i) => <button key={label} id={`${id}-tab-${i}`} role="tab" type="button" aria-selected={tab === i} aria-controls={`${id}-panel`} tabIndex={tab === i ? 0 : -1} onClick={() => setTab(i)} onKeyDown={event => {
        if (["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) {
          event.preventDefault(); const next = event.key === "Home" ? 0 : event.key === "End" ? 1 : 1 - tab;
          setTab(next); document.getElementById(`${id}-tab-${next}`)?.focus();
        }
      }}>{label}<span>{i === 0 ? "↗" : "◎"}</span></button>)}
    </div>
    <div id={`${id}-panel`} role="tabpanel" aria-labelledby={`${id}-tab-${tab}`} tabIndex={0} className={styles.demoPanel}>
      <div className={styles.activityHeading}>{tab === 0 ? c.assetActivity : c.peopleActivity}<span>{c.today}</span></div>
      {items.map((item, i) => <div className={styles.feedItem} key={`${tab}-${item.ticker}`}>
        <div className={styles.feedByline}>{tab === 0 ? <span className={`${styles.tickerBadge} ${i === 1 ? styles.tickerDark : ""}`}>{item.ticker === "NVDA" ? "N" : "a"}</span> : <Avatar letter={item.letter} />}<div><b>{tab === 0 ? item.ticker : item.person}</b><span>{tab === 0 ? item.person : `${c.updatedView} · ${item.ticker}`}</span></div><SourceIcon platform={item.source} /></div>
        <p>{item.quote}</p><div className={styles.feedBottom}><span>{c.newOpinion}</span><span>{c.original} ↗</span></div>
      </div>)}
    </div>
    <div className={styles.demoDisclaimer}>{c.originalLabel}</div>
  </div>;
}
