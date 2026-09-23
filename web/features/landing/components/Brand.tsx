import { BASE_PATH } from "@/lib/site";
import styles from "../landing.module.css";

export function Brand() {
  return <span className={styles.brand}><img src={`${BASE_PATH}/brand/bsmart-wordmark.png`} alt="bSmart" width="991" height="228" /></span>;
}

export function Arrow({ diagonal = false }: { diagonal?: boolean }) {
  return <svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none"><path d={diagonal ? "M6 18 18 6M6 6h12v12" : "M4 12h15m-6-6 6 6-6 6"} stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" /></svg>;
}
