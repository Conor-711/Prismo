import { normalizeWaitlistEmail } from "../../shared/formatting/waitlistEmail";
import { parseWaitlistSurvey } from "../../shared/validation/waitlistSurvey";

interface WaitlistKV {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
}

export interface WaitlistEnvironment {
  WAITLIST?: WaitlistKV;
  // Local Next.js -> Wrangler proxy only. Never enable on a public deployment.
  WAITLIST_LOCAL_DEV?: string;
}

function reply(status: number, code?: string): Response {
  return Response.json(code ? { ok: false, code } : { ok: true }, {
    status,
    headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", ...(status === 405 ? { Allow: "POST" } : {}), ...(status === 429 ? { "Retry-After": "3600" } : {}) },
  });
}

async function digest(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(bytes), byte => byte.toString(16).padStart(2, "0")).join("");
}

async function readBody(request: Request): Promise<string | null> {
  const reader = request.body?.getReader();
  if (!reader) return null;
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > 2048) { await reader.cancel(); return null; }
      chunks.push(value);
    }
    const body = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) { body.set(chunk, offset); offset += chunk.byteLength; }
    return new TextDecoder().decode(body);
  } finally { reader.releaseLock(); }
}

export async function handleWaitlist(request: Request, env: WaitlistEnvironment): Promise<Response> {
  if (request.method !== "POST") return reply(405, "method_not_allowed");
  const url = new URL(request.url);
  const origin = request.headers.get("Origin");
  const allowed = new Set([url.origin, "https://bsmart.today", "https://www.bsmart.today"]);
  if (env.WAITLIST_LOCAL_DEV === "true") {
    allowed.add("http://localhost:3100"); allowed.add("http://127.0.0.1:3100");
  }
  if ((origin && !allowed.has(origin)) || request.headers.get("Sec-Fetch-Site") === "cross-site") return reply(403, "origin_not_allowed");
  if (!request.headers.get("Content-Type")?.toLowerCase().startsWith("application/json")) return reply(415, "json_required");
  if (!env.WAITLIST) return reply(503, "waitlist_unavailable");

  let body: Record<string, unknown>;
  try {
    const text = await readBody(request);
    if (text === null) return reply(413, "body_too_large");
    const parsed: unknown = JSON.parse(text);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return reply(400, "invalid_request");
    body = parsed as Record<string, unknown>;
  } catch { return reply(400, "invalid_request"); }
  const email = typeof body.email === "string" ? normalizeWaitlistEmail(body.email) : null;
  const application = body.intent === "beta-access";
  const legacyConsent = body.intent === undefined && body.consent === true;
  if (!email || (!application && !legacyConsent) || (body.lang !== "zh" && body.lang !== "en") || (body.website !== undefined && body.website !== "")) return reply(400, "invalid_request");
  const survey = parseWaitlistSurvey(body.survey);
  if (survey === null) return reply(400, "invalid_survey");

  try {
    const key = `entry:${await digest(email)}`;
    const previous = await env.WAITLIST.get(key);
    const existing = previous ? JSON.parse(previous) as Record<string, unknown> : null;
    // Allow the original email-only list to receive its first survey, never overwrite answers anonymously.
    if (existing?.survey) return reply(200);
    const ip = request.headers.get("CF-Connecting-IP");
    if (ip) {
      const hour = Math.floor(Date.now() / 3600000);
      const rateKey = `rate:${await digest(`${hour}:${ip}`)}`;
      const count = Number(await env.WAITLIST.get(rateKey) || 0);
      if (!Number.isFinite(count) || count >= 5) return reply(429, "rate_limited");
      // KV is eventually consistent: this is a coarse abuse throttle, not an atomic quota.
      await env.WAITLIST.put(rateKey, String(count + 1), { expirationTtl: 3600 });
    }
    await env.WAITLIST.put(key, JSON.stringify({
      ...(existing ?? {
      email, lang: body.lang, createdAt: new Date().toISOString(), source: "bsmart.today",
      ...(application ? { requestVersion: "beta-application-2026-09-13", requestMethod: "application-button" } : { consentVersion: "beta-invitation-2026-09-13" }),
      }),
      survey, surveyVersion: "investment-interests-required-2026-09-15", surveySubmittedAt: new Date().toISOString(),
    }));
    return reply(200);
  } catch {
    // Do not log request bodies, email addresses, network identifiers or KV errors.
    return reply(503, "waitlist_unavailable");
  }
}
