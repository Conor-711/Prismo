export type ActivityNotice = { id: string; eventKind: "subject" | "native_post" | "native_trade";
  eventID: string; actorID: string; actorName: string; ticker: string; body: string; expiresAt: string };
export type Delivery = { user_id: string; slot_at: string; device_id: string; apns_id: string;
  apns_token: string; locale: string; environment: "production"; item_count: number; device_updated_at: string;
  notice?: ActivityNotice };
export type Result = { status: number | null; invalid: boolean };
export interface PushBackend {
  authorized(token: string): Promise<boolean>;
  prepare(): Promise<void>;
  claim(): Promise<Delivery | null>;
  complete(delivery: Delivery, result: Result): Promise<void>;
  continuePending?(): Promise<void>;
}
export type Sender = { ready(): Promise<void>; send(delivery: Delivery): Promise<Result> };
const reply = (status: number, body: unknown) => Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
export async function handlePush(req: Request, backend: PushBackend, sender: Sender, enabled: boolean, now = Date.now): Promise<Response> {
  if (req.method !== "POST" || !/\/bsmart-push\/dispatch$/.test(new URL(req.url).pathname) || new URL(req.url).search) return reply(404, { error: "not_found" });
  const token = req.headers.get("authorization")?.match(/^Bearer ([a-f0-9]{64})$/)?.[1];
  if (!token) return reply(401, { error: "unauthorized" });
  try {
    if (!await backend.authorized(token)) return reply(401, { error: "unauthorized" });
    if (!enabled) return reply(200, { status: "disabled", attempted: 0 });
    const deadline = now() + 45_000;
    await sender.ready();
    await backend.prepare();
    let attempted = 0, accepted = 0, failed = 0, drained = false, credentialsFailed = false;
    // Reserve time for the claim RPC, Apple request and durable receipt.
    while (attempted < 5 && now() + 24_000 < deadline) {
      const delivery = await backend.claim();
      if (!delivery) { drained = true; break; }
      if (delivery.environment !== "production") throw Error("wrong_environment");
      const result = await sender.send(delivery);
      await backend.complete(delivery, result);
      attempted++; result.status === 200 ? accepted++ : failed++;
      if (result.status === 401 || result.status === 403) { credentialsFailed = true; break; }
    }
    if (attempted > 0 && !drained && !credentialsFailed) await backend.continuePending?.();
    return reply(200, { status: "processed", attempted, accepted, failed });
  } catch { return reply(503, { error: "push_unavailable" }); }
}
