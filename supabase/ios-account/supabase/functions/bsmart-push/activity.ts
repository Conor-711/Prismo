import type { Delivery } from "./handler.ts";

export const NICKNAME_LIMIT = 24, BODY_LIMIT = 160;
const segments = new Intl.Segmenter("zh", { granularity: "grapheme" });
export function truncate(text: string, limit: number): string {
  const characters = Array.from(segments.segment(text), part => part.segment);
  return characters.length <= limit ? text : characters.slice(0, limit - 1).join("") + "…";
}
export function activityPayload(delivery: Delivery) {
  const n = delivery.notice;
  if (!n || !["subject", "native_post", "native_trade"].includes(n.eventKind) ||
    !/^[a-f0-9-]{36}$/.test(n.id) || !n.actorID || n.actorID.length > 160 ||
    !n.eventID || n.eventID.length > 1024 || !n.actorName?.trim() || n.actorName.length > 320 ||
    !/^[A-Z][A-Z0-9.]{0,19}$/.test(n.ticker) || !n.body?.trim() || n.body.length > 16000) {
    throw Error("invalid_activity_notice");
  }
  const name = truncate(n.actorName, NICKNAME_LIMIT);
  return { type: "content_update", actorID: n.actorID, ticker: n.ticker, eventID: n.eventID,
    noticeKind: n.eventKind, aps: { alert: {
      title: `${name}关于$${n.ticker}的最新动态`, body: truncate(n.body, BODY_LIMIT),
    }, sound: "default", "thread-id": "bsmart.activity" } };
}
