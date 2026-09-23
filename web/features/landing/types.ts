import type { Dictionary } from "@/lib/i18n";

export type LandingCopy = Dictionary["betaLanding"];

export type WaitlistCopy = Pick<LandingCopy, "survey" | "tagline" | "email" | "emailPlaceholder" | "apply" | "applied" | "submitting" | "invalidEmail" | "tooMany" | "unavailable" | "networkError">;
