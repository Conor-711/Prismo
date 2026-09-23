"use client";

import { FormEvent, useRef, useState } from "react";
import { BASE_PATH } from "@/lib/site";
import { normalizeWaitlistEmail } from "@/shared/formatting/waitlistEmail";
import { INVESTMENT_CHANNELS, parseWaitlistSurvey } from "@/shared/validation/waitlistSurvey";
import type { WaitlistCopy } from "../types";
import { Arrow } from "./Brand";
import styles from "../landing.module.css";

export function WaitlistForm({ copy: c, lang }: { copy: WaitlistCopy; lang: string }) {
  const [state, setState] = useState<"idle" | "submitting" | "success" | "error">("idle");
  const [message, setMessage] = useState("");
  const emailInput = useRef<HTMLInputElement>(null);
  const inFlight = useRef(false);
  const [otherSelected, setOtherSelected] = useState(false);
  const otherInput = useRef<HTMLInputElement>(null);
  const firstChannel = useRef<HTMLInputElement>(null);
  const contactInput = useRef<HTMLInputElement>(null);
  const locked = state === "submitting" || state === "success";

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (inFlight.current || state === "success") return;
    const data = new FormData(event.currentTarget);
    const email = normalizeWaitlistEmail(String(data.get("email") || ""));
    if (!email) { setState("error"); setMessage(c.invalidEmail); emailInput.current?.focus(); return; }
    if (data.getAll("channels").length === 0) { setState("error"); setMessage(c.survey.channelsRequired); firstChannel.current?.focus(); return; }
    if (otherSelected && !String(data.get("otherChannel") || "").trim()) { setState("error"); setMessage(c.survey.invalid); otherInput.current?.focus(); return; }
    const handle = String(data.get("handle") || "").trim();
    if (!handle) { setState("error"); setMessage(c.survey.contactRequired); contactInput.current?.focus(); return; }
    const survey = parseWaitlistSurvey({
      channels: data.getAll("channels"), otherChannel: otherSelected ? String(data.get("otherChannel") || "") : "",
      contact: handle ? { platform: data.get("platform"), handle } : null,
    });
    if (!survey) { setState("error"); setMessage(c.survey.invalid); otherInput.current?.focus(); return; }
    inFlight.current = true;
    setState("submitting"); setMessage("");
    try {
      const response = await fetch(`${BASE_PATH}/api/waitlist`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, survey, intent: "beta-access", lang: lang === "zh" ? "zh" : "en", website: String(data.get("website") || "") }),
        signal: AbortSignal.timeout(15000),
      });
      const result: { ok?: boolean; code?: string } = await response.json().catch(() => ({}));
      if (!response.ok || result.ok !== true) {
        setState("error");
        setMessage(response.status === 429 ? c.tooMany : result.code === "invalid_survey" ? c.survey.invalid : response.status === 400 ? c.invalidEmail : c.unavailable);
        return;
      }
      setState("success");
    } catch { setState("error"); setMessage(c.networkError); }
    finally { inFlight.current = false; }
  }

  return <div className={styles.waitlistForm}>
    <form onSubmit={submit} noValidate aria-busy={state === "submitting"} onChange={() => { if (!locked) { setState("idle"); setMessage(""); } }}>
      <label className={styles.fieldTitle} htmlFor="waitlist-email"><span className={styles.fieldNumber} aria-hidden="true">01</span>{c.email}</label>
      <input className={styles.textInput} ref={emailInput} id="waitlist-email" name="email" type="email" inputMode="email" autoComplete="email" autoCapitalize="none" spellCheck={false} maxLength={254} required placeholder={c.emailPlaceholder} aria-describedby={message ? "waitlist-message" : undefined} aria-invalid={state === "error" && message === c.invalidEmail} disabled={locked} />
      <fieldset className={styles.question} disabled={locked} aria-describedby={message === c.survey.channelsRequired ? "waitlist-message" : undefined}>
        <legend><span className={styles.fieldNumber} aria-hidden="true">02</span>{c.survey.channels}<small>{c.survey.multiple}</small></legend>
        <div className={styles.channelGrid}>
          {INVESTMENT_CHANNELS.map(channel => {
            const detail = channel === "accounts" ? c.survey.accountsDetail : channel === "politicians" ? c.survey.politiciansDetail : channel === "insiders" ? c.survey.insidersDetail : null;
            return <label key={channel} className={styles.channelOption}>
              <input ref={channel === "accounts" ? firstChannel : undefined} type="checkbox" name="channels" value={channel} aria-invalid={message === c.survey.channelsRequired} onChange={channel === "other" ? event => setOtherSelected(event.target.checked) : undefined} />
              <span>{c.survey[channel]}{detail && <small>{detail}</small>}</span>
            </label>;
          })}
        </div>
        {otherSelected && <input className={styles.textInput} ref={otherInput} name="otherChannel" aria-label={c.survey.otherPlaceholder} placeholder={c.survey.otherPlaceholder} maxLength={200} required aria-invalid={message === c.survey.invalid} aria-describedby={message ? "waitlist-message" : undefined} />}
      </fieldset>
      <fieldset className={styles.question} disabled={locked}>
        <legend><span className={styles.fieldNumber} aria-hidden="true">03</span>{c.survey.contact}</legend>
        <div className={styles.contactRow}>
          <select name="platform" aria-label={c.survey.platform} defaultValue="telegram" required>
            <option value="telegram">Telegram</option><option value="wechat">{c.survey.wechat}</option><option value="twitter">Twitter / X</option>
          </select>
          <input ref={contactInput} className={styles.textInput} name="handle" aria-label={c.survey.handle} placeholder={c.survey.handlePlaceholder} maxLength={120} autoCapitalize="none" spellCheck={false} required aria-invalid={message === c.survey.contactRequired} aria-describedby={message === c.survey.contactRequired ? "waitlist-message" : undefined} />
        </div>
      </fieldset>
      <button className={styles.submitButton} type="submit" disabled={locked}>{state === "success" ? c.applied : state === "submitting" ? c.submitting : c.apply}{state === "success" ? <span aria-hidden="true">✓</span> : <Arrow />}</button>
      <div className={styles.honeypot} aria-hidden="true"><label htmlFor="waitlist-website">Website</label><input id="waitlist-website" name="website" type="text" tabIndex={-1} autoComplete="off" /></div>
      {message && <p className={styles.formError} id="waitlist-message" role="alert">{message}</p>}
      <span className={styles.srOnly} role="status">{state === "success" ? c.applied : ""}</span>
    </form>
  </div>;
}
