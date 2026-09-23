import { getDictionary } from "@/lib/i18n";
import { BrowserWaitlist } from "./components/BrowserWaitlist";
import type { WaitlistCopy } from "./types";

function formCopy(lang: "zh" | "en"): WaitlistCopy {
  const { survey, tagline, email, emailPlaceholder, apply, applied, submitting, invalidEmail, tooMany, unavailable, networkError } = getDictionary(lang).betaLanding;
  return { survey, tagline, email, emailPlaceholder, apply, applied, submitting, invalidEmail, tooMany, unavailable, networkError };
}

export function LandingPage() {
  return <BrowserWaitlist copy={{ zh: formCopy("zh"), en: formCopy("en") }} />;
}
