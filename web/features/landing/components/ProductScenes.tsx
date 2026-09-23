import { BASE_PATH } from "@/lib/site";
import type { LandingCopy } from "../types";
import styles from "../landing.module.css";

export function SourceIcon({ platform }: { platform: "x" | "youtube" | "reddit" }) {
  return <img className={styles.sourceIcon} src={`${BASE_PATH}/platform/${platform}.png`} width="18" height="18" alt={platform === "x" ? "X" : platform === "youtube" ? "YouTube" : "Reddit"} />;
}

export function Avatar({ letter = "A", variant = 0 }: { letter?: string; variant?: number }) {
  return <span aria-hidden="true" className={`${styles.avatar} ${variant === 1 ? styles.avatarBlue : variant === 2 ? styles.avatarPeach : ""}`}>{letter}</span>;
}

export function HeroScene({ copy: c }: { copy: LandingCopy }) {
  return <div className={styles.heroScene} aria-label={c.demo}>
    <div className={styles.orbit} aria-hidden="true" /><div className={styles.orbitInner} aria-hidden="true" />
    <span className={styles.sceneLabel}>{c.demo}</span>
    <div className={styles.phone}>
      <div className={styles.phoneStatus} aria-hidden="true"><span>9:41</span><span>▰ ▰ ▰</span></div>
      <div className={styles.phoneHeading}><span className={styles.phoneBrand}>b<span>Smart</span></span><span className={styles.smallAvatar}>Y</span></div>
      <div className={styles.phoneTitle}>{c.following}<span>↗</span></div>
      <div className={styles.stockStrip}><b>NVDA</b><b>AAPL</b><b>MSFT</b></div>
      <div className={styles.phoneStory}><span className={styles.stockLabel}>NVIDIA <span>NVDA</span></span><h3>{c.demoOpinion1}</h3><div className={styles.miniByline}><Avatar /><span>{c.researcher}</span><SourceIcon platform="x" /></div><span className={styles.originalTag}>{c.original} ↗</span></div>
      <div className={styles.phoneActivity}><Avatar letter="B" variant={1} /><div><b>{c.researcherB}</b><span>{c.updatedView} · AAPL</span></div><span>↗</span></div>
      <div className={styles.phoneActivity}><Avatar letter="C" variant={2} /><div><b>{c.researcherC}</b><span>{c.firstView} · MSFT</span></div><span>↗</span></div>
      <div className={styles.phoneNav} aria-hidden="true"><span>◉</span><span>▤</span><span>◎</span><span>◯</span></div>
      <span className={styles.phoneHome} aria-hidden="true" />
    </div>
    <div className={styles.floatingSource}><span className={styles.sourceCheck}>↗</span><div><b>{c.evidence}</b><span>X · YouTube · Reddit</span></div></div>
    <div className={styles.floatingAsset}><span className={styles.nvidiaMark}>N</span><div><b>NVDA</b><span>{c.newOpinion}</span></div><span className={styles.notificationDot} /></div>
  </div>;
}

export function PeopleScene({ copy: c }: { copy: LandingCopy }) {
  return <div className={styles.peopleScene}>
    <span className={styles.sceneLabel}>{c.demo}</span>
    <div className={styles.peopleCard}>
      <div className={styles.profileTop}><Avatar /><span className={styles.followingPill}>✓ {c.follow}</span></div>
      <div className={styles.profileName}>{c.researcher}<span>{c.profile}</span></div>
      <div className={styles.focusTags}><span>{c.semiconductor}</span><span>{c.consumer}</span></div>
      <div className={styles.recordTitle}>{c.history}<span>↗</span></div>
      <div className={styles.historyRow}><span className={styles.historyDot} /><div><b>NVDA</b><p>{c.demoOpinion1}</p><SourceIcon platform="x" /></div></div>
      <div className={styles.historyRow}><span className={styles.historyDot} /><div><b>MSFT</b><p>{c.demoOpinion3}</p><SourceIcon platform="youtube" /></div></div>
    </div>
    <div className={styles.historySeal}><span>↗</span>{c.evidence}</div>
  </div>;
}
