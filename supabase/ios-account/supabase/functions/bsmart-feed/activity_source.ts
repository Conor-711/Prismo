import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { uuid } from "./verification.ts";

type Reference = { kind: "subject"; subjectID: string; eventID: string } |
  { kind: "native"; updateID: string };

export function activityReference(input: unknown): Reference | null {
  if (input === undefined) return null;
  if (!input || typeof input !== "object" || Array.isArray(input)) throw Error("invalid_input");
  const source = input as Record<string, unknown>;
  if (source.kind === "subject" && Object.keys(source).sort().join() === "eventID,kind,subjectID" &&
      typeof source.subjectID === "string" &&
      /^(politician|celebrity|institution):[A-Za-z0-9_-]{1,80}$/.test(source.subjectID) &&
      typeof source.eventID === "string" && source.eventID.length > 0 && source.eventID.length <= 256) {
    return source as Reference;
  }
  if (source.kind === "native" && Object.keys(source).sort().join() === "kind,updateID" && uuid(source.updateID)) {
    return source as Reference;
  }
  throw Error("invalid_input");
}

export function sameActivityReference(stored: any, source: Reference | null): boolean {
  if (!source) return stored == null;
  return stored?.kind === source.kind && (source.kind === "subject"
    ? stored.subjectID === source.subjectID && stored.eventID === source.eventID
    : String(stored.updateID).toLowerCase() === source.updateID.toLowerCase());
}

export async function verifiedActivity(client: SupabaseClient, source: Reference, ticker: string) {
  if (source.kind === "subject") {
    const { data, error } = await client.rpc("bsmart_subject_activity_read", { p_subject_id: source.subjectID });
    if (error) throw Error("source_unavailable");
    const subject = data?.subjects?.find((item: any) => item?.id === source.subjectID);
    const event = data?.events?.find((item: any) => item?.id === source.eventID && item?.subjectID === source.subjectID);
    const linkedTicker = event?.ticker ?? (event?.type === "holding" ? event?.underlyingTicker : null);
    if (!subject || !event || typeof linkedTicker !== "string" ||
        linkedTicker.toUpperCase() !== ticker.toUpperCase() ||
        !["trade", "opinion", "holding"].includes(event.type)) throw Error("source_unavailable");
    const summary = typeof event.summary === "string" && event.summary.trim()
      ? event.summary.trim() : `${event.action ?? event.direction ?? event.type} ${ticker}`;
    return { kind: "subject", subjectID: source.subjectID, eventID: source.eventID,
      authorName: String(subject.name ?? "").slice(0, 100), avatarURL: subject.avatarURL ?? null,
      body: summary.slice(0, 8000), subjectEvent: event };
  }

  const { data, error } = await client.rpc("bsmart_native_investor_snapshot");
  if (error) throw Error("source_unavailable");
  const update = data?.updates?.find((item: any) =>
    typeof item?.id === "string" && item.id.toLowerCase() === source.updateID.toLowerCase());
  if (!update || update.ticker?.toUpperCase() !== ticker.toUpperCase() || !update.publicID) {
    throw Error("source_unavailable");
  }
  return { kind: "native", updateID: source.updateID,
    authorID: `bsmart:${update.publicID}`, authorName: String(update.nickname ?? "").slice(0, 100),
    avatarURL: update.avatarURL ?? null, body: String(update.body ?? "").slice(0, 8000),
    ticker: update.ticker, platform: "bsmart", publishedAt: update.publishedAt,
    direction: update.reducing ? "neutral" : update.side === "long" ? "bullish" : "bearish" };
}
