export type LandingLanguage = "zh" | "en";

// Only the primary browser preference counts; a secondary Chinese preference
// must not override a non-Chinese default language.
export function landingLanguage(primaryLanguage?: string): LandingLanguage {
  return /^zh(?:[-_]|$)/i.test(primaryLanguage || "") ? "zh" : "en";
}
