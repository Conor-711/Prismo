import { strict as assert } from "node:assert";
import { exportPKCS8, generateKeyPair } from "npm:jose@5.10.0";
import { activityPayload, truncate } from "../supabase/functions/bsmart-push/activity.ts";
import { apnsSender } from "../supabase/functions/bsmart-push/apns.ts";
import type { Delivery } from "../supabase/functions/bsmart-push/handler.ts";

const delivery = (): Delivery => ({ user_id: crypto.randomUUID(), device_id: crypto.randomUUID(),
  apns_id: crypto.randomUUID(), slot_at: "2026-10-01T10:00:00Z", apns_token: "b".repeat(64),
  locale: "zh-Hans", environment: "production", item_count: 1, device_updated_at: "2026-10-01T09:00:00Z",
  notice: { id: crypto.randomUUID(), eventKind: "subject", eventID: "event", actorID: "politician:ken",
    actorName: "Ken Hern", ticker: "AAPL", body: "Original text\n第二行", expiresAt: "2026-10-02T10:00:00Z" } });
Deno.test("activity notifications use original body and truncate without breaking emoji", () => {
  const d = delivery();
  assert.deepEqual(activityPayload(d).aps.alert, { title: "Ken Hern关于$AAPL的最新动态", body: "Original text\n第二行" });
  const emoji = "👨‍👩‍👧‍👦";
  assert.equal(truncate(emoji.repeat(25), 24), emoji.repeat(23) + "…");
  d.notice!.actorName = "名".repeat(25); d.notice!.body = "字".repeat(161);
  const payload = activityPayload(d);
  assert.equal(payload.type, "content_update");
  assert.equal(payload.aps.alert.title, "名".repeat(23) + "…关于$AAPL的最新动态");
  assert.equal(payload.aps.alert.body, "字".repeat(159) + "…");
  assert.throws(() => activityPayload({ ...d, notice: undefined }));
  assert.throws(() => activityPayload({ ...d, notice: { ...d.notice!, ticker: "not a ticker" } }));
});
Deno.test("individual notices stay distinct and valid after old digest window, but expire after 24 hours", async () => {
  const key = await generateKeyPair("ES256", { extractable: true });
  const privateKey = await exportPKCS8(key.privateKey);
  let clock = Date.parse("2026-10-01T13:00:00Z");
  const collapse: string[] = [];
  const sender = apnsSender({ team: "AAAAAAAAAA", keyId: "BBBBBBBBBB", topic: "today.bsmart.ios", privateKey },
    async (_url, init) => {
      const headers = new Headers(init?.headers);
      collapse.push(headers.get("apns-collapse-id")!);
      assert.ok(new TextEncoder().encode(String(init?.body)).length <= 4096);
      assert.equal(JSON.parse(String(init?.body)).type, "content_update");
      assert.equal(headers.get("apns-expiration"), String(Date.parse("2026-10-02T10:00:00Z") / 1000));
      return new Response(null, { status: 200 });
    }, () => clock, undefined, activityPayload);
  assert.equal((await sender.send(delivery())).status, 200);
  assert.equal((await sender.send(delivery())).status, 200);
  assert.notEqual(collapse[0], collapse[1]);
  clock = Date.parse("2026-10-02T10:00:00Z");
  assert.equal((await sender.send(delivery())).status, null);
  assert.equal(collapse.length, 2);
});
