import { strict as assert } from "node:assert";
import { exportPKCS8, generateKeyPair, jwtVerify } from "npm:jose@5.10.0";
import { apnsSender, digestPayload } from "../supabase/functions/bsmart-push/apns.ts";
import { Delivery, handlePush, PushBackend } from "../supabase/functions/bsmart-push/handler.ts";

const time = Date.parse("2026-10-01T10:01:00Z"), token = "a".repeat(64);
const delivery = (): Delivery => ({ user_id: crypto.randomUUID(), device_id: crypto.randomUUID(),
  apns_id: crypto.randomUUID(), slot_at: "2026-10-01T10:00:00Z", apns_token: "b".repeat(64),
  locale: "zh-Hans", environment: "production", item_count: 2, device_updated_at: "2026-10-01T09:00:00Z" });
const req = (auth = "Bearer " + token) => new Request("https://test.invalid/bsmart-push/dispatch", { method: "POST", headers: { authorization: auth } });
function mock(status: number | null = 200) {
  const state = { auth: true, prepared: 0, claimed: 0, sent: 0, complete: 0, ready: 0 };
  const backend: PushBackend = { authorized: async t => t === token && state.auth,
    prepare: async () => { state.prepared++; }, claim: async () => { state.claimed++; return state.claimed <= 7 ? delivery() : null; },
    complete: async () => { state.complete++; } };
  const sender = { ready: async () => { state.ready++; }, send: async () => { state.sent++; return { status, invalid: false }; } };
  return { backend, sender, state };
}
Deno.test("cloud push rejects user JWTs and wrong worker token before touching devices or APNs", async () => {
  const m = mock();
  for (const auth of ["", "Bearer a.b.c", "Bearer " + "c".repeat(64)]) assert.equal((await handlePush(req(auth), m.backend, m.sender, true)).status, 401);
  assert.equal(m.state.ready, 0); assert.equal(m.state.claimed, 0);
});
Deno.test("cloud push remains disabled before credential checks and sends bounded batches", async () => {
  const m = mock();
  assert.equal((await handlePush(req(), m.backend, m.sender, false)).status, 200);
  assert.equal(m.state.ready, 0); assert.equal(m.state.prepared, 0);
  const result = await handlePush(req(), m.backend, m.sender, true, () => time);
  assert.deepEqual(await result.json(), { status: "processed", attempted: 5, accepted: 5, failed: 0 });
  assert.equal(m.state.sent, 5); assert.equal(m.state.complete, 5);
});
Deno.test("cloud push checks credentials before claiming and never retries uncertain sends", async () => {
  const m = mock(null);
  m.sender.ready = () => { throw Error("secret private key failed"); };
  let result = await handlePush(req(), m.backend, m.sender, true);
  assert.equal(result.status, 503); assert.equal(m.state.claimed, 0);
  assert.deepEqual(await result.json(), { error: "push_unavailable" });
  m.sender.ready = async () => {};
  result = await handlePush(req(), m.backend, m.sender, true, () => time);
  assert.equal((await result.json()).failed, 5); assert.equal(m.state.sent, 5);
  m.backend.complete = () => { throw Error("receipt lost"); };
  m.state.claimed = 0; m.state.sent = 0;
  assert.equal((await handlePush(req(), m.backend, m.sender, true, () => time)).status, 503);
  assert.equal(m.state.sent, 1);
});
Deno.test("cloud push stops on credential outage and budget expiry without claiming more", async () => {
  const m = mock(403);
  const result = await handlePush(req(), m.backend, m.sender, true, () => time);
  assert.equal((await result.json()).attempted, 1); assert.equal(m.state.claimed, 1);
  const n = mock(); let clock = time;
  n.sender.ready = async () => { clock += 34_000; };
  await handlePush(req(), n.backend, n.sender, true, () => clock);
  assert.equal(n.state.claimed, 0);
});
Deno.test("activity worker schedules a continuation only after a bounded batch, not a credential failure", async () => {
  const m = mock(); let wakeups = 0;
  m.backend.continuePending = async () => { wakeups++; };
  await handlePush(req(), m.backend, m.sender, true, () => time);
  assert.equal(wakeups, 1);
  const failed = mock(403);
  failed.backend.continuePending = async () => { wakeups++; };
  await handlePush(req(), failed.backend, failed.sender, true, () => time);
  assert.equal(wakeups, 1);
  const empty = mock(); empty.backend.claim = async () => null;
  empty.backend.continuePending = async () => { wakeups++; };
  await handlePush(req(), empty.backend, empty.sender, true, () => time);
  assert.equal(wakeups, 1);
});
Deno.test("APNs sender signs ES256 and fixes production host/topic, without holdings or identity in payload", async () => {
  const keys = await generateKeyPair("ES256", { extractable: true }), privateKey = await exportPKCS8(keys.privateKey);
  let clock = time, calls = 0;
  const seen: string[] = [];
  const sender = apnsSender({ team: "AAAAAAAAAA", keyId: "BBBBBBBBBB", topic: "today.bsmart.ios", privateKey }, async (url, init) => {
    calls++; assert.ok(String(url).startsWith("https://api.push.apple.com/3/device/"));
    const headers = new Headers(init?.headers), signed = headers.get("authorization")!.slice(7); seen.push(signed);
    const verified = await jwtVerify(signed, keys.publicKey, { algorithms: ["ES256"], issuer: "AAAAAAAAAA", currentDate: new Date(clock) });
    assert.equal(verified.protectedHeader.kid, "BBBBBBBBBB");
    assert.equal(headers.get("apns-topic"), "today.bsmart.ios"); assert.equal(headers.get("apns-push-type"), "alert");
    assert.equal(init?.redirect, "error");
    const body = JSON.parse(String(init?.body)); assert.ok(!JSON.stringify(body).includes("user_id"));
    assert.equal(body.aps.sound, "default"); return new Response(null, { status: 200 });
  }, () => clock);
  await sender.ready(); await sender.send(delivery()); await sender.send(delivery());
  assert.equal(calls, 2); assert.equal(seen[0], seen[1]);
  assert.ok(digestPayload(delivery()).aps.alert.body.includes("2"));
  clock += 30 * 60_000;
  assert.equal((await sender.send(delivery())).status, null); assert.equal(calls, 2);
  const invalid = apnsSender({ team: "AAAAAAAAAA", keyId: "BBBBBBBBBB", topic: "wrong.bundle", privateKey }, fetch);
  await assert.rejects(() => invalid.ready());
});
Deno.test("APNs treats lost responses as uncertain, invalid tokens separately, and has no network retry", async () => {
  const keys = await generateKeyPair("ES256", { extractable: true }), privateKey = await exportPKCS8(keys.privateKey);
  let calls = 0;
  const sender = apnsSender({ team: "AAAAAAAAAA", keyId: "BBBBBBBBBB", topic: "today.bsmart.ios", privateKey }, () => {
    calls++; throw Error("timeout");
  }, () => time);
  assert.deepEqual(await sender.send(delivery()), { status: null, invalid: false }); assert.equal(calls, 1);
  const unregistered = apnsSender({ team: "AAAAAAAAAA", keyId: "BBBBBBBBBB", topic: "today.bsmart.ios", privateKey }, () =>
    Promise.resolve(Response.json({ reason: "Unregistered" }, { status: 410 })), () => time);
  assert.deepEqual(await unregistered.send(delivery()), { status: 410, invalid: true });
});

Deno.test("cold APNs workers reuse the durable JWT and fail closed when its cache is unavailable", async () => {
  const keys = await generateKeyPair("ES256", { extractable: true }), privateKey = await exportPKCS8(keys.privateKey);
  const config = { team: "AAAAAAAAAA", keyId: "BBBBBBBBBB", topic: "today.bsmart.ios", privateKey };
  let shared: { token: string; expires_at: string } | null = null;
  const cache = { exchange: async (identity: string, candidate?: string) => {
    assert.equal(identity, "AAAAAAAAAA:BBBBBBBBBB:today.bsmart.ios");
    if (!shared && candidate) shared = { token: candidate, expires_at: new Date(time + 45 * 60_000).toISOString() };
    return shared;
  } };
  const seen: string[] = [];
  const transport: typeof fetch = (_url, init) => {
    seen.push(new Headers(init?.headers).get("authorization")!);
    return Promise.resolve(new Response(null, { status: 200 }));
  };
  const a = apnsSender(config, transport, () => time, cache);
  await a.ready(); await a.send(delivery());
  const b = apnsSender({ ...config, privateKey: "not used while cached" }, transport, () => time + 60_000, cache);
  await b.ready(); await b.send(delivery());
  assert.equal(seen[0], seen[1]);
  const unavailable = apnsSender(config, () => { throw Error("must not send"); }, () => time, {
    exchange: () => Promise.reject(Error("database unavailable")),
  });
  await assert.rejects(() => unavailable.ready());
});
