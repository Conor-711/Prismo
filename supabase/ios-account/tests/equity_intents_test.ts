import { strict as assert } from "node:assert";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { MarketError } from "../supabase/functions/bsmart-markets/routing.ts";
import { createInput, expectedVersion, intentResponse, type IntentRow, type Ledger, recoveryAction, refreshable,
  requestHash, savedPreview } from "../supabase/functions/bsmart-equities/intents.ts";
import { handleEquities } from "../supabase/functions/bsmart-equities/handler.ts";
import { equityLedger } from "../supabase/functions/bsmart-equities/ledger.ts";
import type { EVMCatalogs } from "../supabase/functions/bsmart-equities/routing.ts";
import type { PreviewPorts } from "../supabase/functions/bsmart-equities/preview.ts";
import { NETWORKS } from "../supabase/functions/bsmart-equities/assets.ts";

const fixture = JSON.parse(await Deno.readTextFile(new URL("../../../contracts/fixtures/evm-equity-intent.json", import.meta.url)));
const at = Date.parse("2026-10-01T00:00:00Z"), owner = fixture.response.intent.owner;
const account = "12345678-1234-1234-1234-123456789abc", id = fixture.response.intent.id, other = "98765432-1234-1234-1234-123456789abc";
const input = fixture.createRequest.input, token = "0x1111111111111111111111111111111111111111";
const row = (): IntentRow => ({ id, client_intent_id: fixture.createRequest.clientIntentId, account_id: account,
  wallet_address: owner, request_hash: "a".repeat(64), input, state: "draft", version: 0, preview: null,
  quote_expires_at: null, created_at: new Date(at).toISOString(), updated_at: new Date(at).toISOString() });
const catalogs: EVMCatalogs = (() => {
  const asset = { id: account, symbol: "ASTSx", ticker: "ASTS", name: "ASTS", halted: false, tradingHours: null,
    deployments: [{ network: "Ethereum" as const, token, usdc: NETWORKS.Ethereum.usdc, wrapperV2: null }] };
  return { hl: async () => ({ at, values: [] }), registry: async () => ({ at, values: [asset] }), asset: async () => ({ at, values: [asset] }) };
})();
const ports = (): PreviewPorts => ({ state: async i => ({ at, chainId: i.chainId, owner, token, usdc: i.usdc,
  block: "100", blockTimestamp: at / 1000, tokenDecimals: 18, usdcDecimals: 6, tokenBalance: "0", usdcBalance: "100000000",
  tokenAllowance: "0", usdcAllowance: "0", multiplier: "1000000000000000000", multiplierNonce: "0", activationTime: 0 }),
  quote: async (_i, q) => ({ from: owner, expiration: new Date(at + 60000).toISOString(), id: 1, verified: false,
    quote: { ...q, sellAmount: "99500000", feeAmount: "500000", buyAmount: "2000000000000000000", partiallyFillable: false } }),
});
function client(bound = owner, userAccount = account): SupabaseClient {
  return { auth: { getUser: async () => ({ data: { user: { id: userAccount, identities: [{ provider: "apple" }] } }, error: null }) },
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: bound ? { address: bound } : null, error: null }) }) }) }) } as unknown as SupabaseClient;
}
// Models storage for HTTP orchestration tests, not a substitute for PostgreSQL/RLS tests.
function memoryLedger() {
  let current: IntentRow | undefined;
  const ledger: Ledger = {
    create: async (a, o, c, i, h) => {
      if (current && (current.account_id !== a || current.wallet_address !== o || current.request_hash !== h || current.client_intent_id !== c)) throw new MarketError("intent_idempotency_conflict", 409);
      current ??= { ...row(), account_id: a, wallet_address: o, client_intent_id: c, input: i, request_hash: h };
      return structuredClone(current);
    },
    get: async (a, uuid) => {
      if (!current || current.account_id !== a || current.id !== uuid) throw new MarketError("intent_not_found", 404);
      return structuredClone(current);
    },
    legs: async () => [],
    change: async (a, uuid, o, v, action, preview) => {
      if (!current || current.account_id !== a || current.id !== uuid) throw new MarketError("intent_not_found", 404);
      if (action === "cancel" && current.state === "cancelled" && [current.version, current.version - 1].includes(v)) return structuredClone(current);
      refreshable(current, o, v);
      current = { ...current, state: action === "quote" ? "quoted" : "cancelled", version: current.version + 1,
        preview: preview ?? current.preview, quote_expires_at: preview ? savedPreview(current, preview, at) : current.quote_expires_at };
      return structuredClone(current);
    },
  };
  return ledger;
}
const request = (path: string, body?: unknown) => new Request("https://test.invalid/bsmart-equities/" + path,
  { method: body === undefined ? "GET" : "POST", headers: { authorization: "Bearer a.b.c", "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
const options = (ledger: Ledger) => ({ catalogs, discoveryEnabled: true, ledgerEnabled: true, ledger,
  previewEnabled: true, previewPorts: ports(), now: () => at });

Deno.test("intent inputs reject owner, chain, signature, unexpected keys and invalid versions", () => {
  assert.deepEqual(createInput(fixture.createRequest), fixture.createRequest);
  for (const v of [null, [], {}, { ...fixture.createRequest, owner }, { ...fixture.createRequest, clientIntentId: "not-uuid" },
    { ...fixture.createRequest, input: { ...input, chainId: 1 } }]) assert.throws(() => createInput(v));
  for (const amount of ["100001", "1.0000001"]) assert.throws(() => createInput({ ...fixture.createRequest, input: { ...input, amount } }));
  for (const v of [null, [], {}, { expectedVersion: -1 }, { expectedVersion: 0.5 }, { expectedVersion: "0" },
    { expectedVersion: 2147483647 }, { expectedVersion: 0, signature: "x" }]) assert.throws(() => expectedVersion(v));
  assert.equal(expectedVersion({ expectedVersion: 0 }), 0);
});
Deno.test("intent hash is order-independent but binds account, owner and every constraint", async () => {
  const hash = await requestHash(account, owner, input);
  assert.equal(hash, await requestHash(account, owner, { maxNetworkFeeBps: 100, amount: "100", side: "buy", ticker: "ASTS", slippageBps: 50 }));
  for (const patch of [{ amount: "101" }, { side: "sell" }, { ticker: "SPY" }, { slippageBps: 51 }, { maxNetworkFeeBps: 101 }, { minimumOutput: "1" }]) {
    assert.notEqual(hash, await requestHash(account, owner, { ...input, ...patch }));
  }
  assert.notEqual(hash, await requestHash(other, owner, input));
  assert.notEqual(hash, await requestHash(account, token, input));
});
Deno.test("intent read serialization does not expose lease credentials, evidence or account internals", () => {
  assert.deepEqual(intentResponse(row()), fixture.response);
  const result = intentResponse(row(), [{ id, kind: "order", state: "unknown", provider: "cow", provider_id: "0xabc", attempts: 1,
    checked_at: null, lease_id: "secret", leased_until: "later", evidence_hash: "secret" } as any]);
  assert.equal(JSON.stringify(result).includes("secret"), false);
  assert.equal(Object.hasOwn(result.intent, "request_hash"), false);
});
Deno.test("attempt lease expiration and process restart never authorize resubmission", () => {
  assert.equal(recoveryAction({ state: "reserved", attempts: 0 }, null, at), "claim");
  assert.equal(recoveryAction({ state: "submitting", attempts: 1 }, at + 1000, at), "wait");
  for (const state of ["submitting", "submitted", "unknown"] as const) {
    assert.equal(recoveryAction({ state, attempts: 1 }, at - 1, at), "reconcile_only");
    assert.notEqual(recoveryAction({ state, attempts: 1 }, null, at), "claim");
  }
  for (const state of ["confirmed", "failed"] as const) assert.equal(recoveryAction({ state, attempts: 1 }, at - 1, at), "terminal");
});
Deno.test("intent refresh refuses wallet changes, stale versions and execution states", () => {
  refreshable(row(), owner, 0);
  assert.throws(() => refreshable(row(), token, 0)); assert.throws(() => refreshable(row(), owner, 1));
  for (const state of ["authorized", "order_pending", "needs_reconciliation", "cancelled"] as const) assert.throws(() => refreshable({ ...row(), state }, owner, 0));
});
Deno.test("authenticated intent create retries persist one draft without calling providers", async () => {
  const ledger = memoryLedger(), opts = options(ledger);
  opts.catalogs = { hl: () => { throw new Error("unexpected provider call"); }, registry: () => { throw new Error(); }, asset: () => { throw new Error(); } };
  const results = await Promise.all([1, 2, 3].map(() => handleEquities(request("intents", fixture.createRequest), client(), opts)));
  for (const r of results) { assert.equal(r.status, 200); assert.deepEqual(await r.json(), fixture.response); }
  const conflict = await handleEquities(request("intents", { ...fixture.createRequest, input: { ...input, amount: "101" } }), client(), opts);
  assert.equal(conflict.status, 409);
  assert.equal((await handleEquities(request("intents", fixture.createRequest), client(token), opts)).status, 409);
});
Deno.test("intent HTTP gates and cross-account reads do not leak records or allow execution", async () => {
  const ledger = memoryLedger(), opts = options(ledger);
  assert.equal((await handleEquities(request("intents", fixture.createRequest), client(), { ...opts, ledgerEnabled: false })).status, 503);
  await handleEquities(request("intents", fixture.createRequest), client(), opts);
  assert.equal((await handleEquities(request("intents/" + id), client(owner, other), opts)).status, 404);
  assert.equal((await handleEquities(request("intents/nope"), client(), opts)).status, 422);
  assert.equal((await handleEquities(request("intents/" + id + "?owner=" + owner), client(), opts)).status, 422);
  for (const action of ["authorize", "submit", "sign", "transfer", "approve"]) {
    assert.equal((await handleEquities(request("intents/" + id + "/" + action, {}), client(), opts)).status, 404);
  }
  const unauth = request("intents/" + id); unauth.headers.delete("authorization");
  assert.equal((await handleEquities(unauth, client(), opts)).status, 401);
});
Deno.test("intent quote refresh persists only a server-produced non-executable preview", async () => {
  const ledger = memoryLedger(), opts = options(ledger);
  await handleEquities(request("intents", fixture.createRequest), client(), opts);
  const quote = await handleEquities(request("intents/" + id + "/preview", { expectedVersion: 0 }), client(), opts);
  assert.equal(quote.status, 200);
  const body = await quote.json(); assert.equal(body.intent.state, "quoted"); assert.equal(body.intent.version, 1);
  assert.equal(body.executionEnabled, false); assert.equal(body.intent.preview.candidates[0].executable, false);
  const stored = await ledger.get(account, id);
  for (const patch of [{ executionEnabled: true }, { returnTransferImplemented: true }, { gasCoverage: "sponsored" },
    { ticker: "SPY" }, { candidates: [{ ...stored.preview!.candidates[0], owner: token }] },
    { candidates: [{ ...stored.preview!.candidates[0], expiresAt: new Date(at + 1).toISOString() }] }]) {
    assert.throws(() => savedPreview(stored, { ...stored.preview!, ...patch } as any, at));
  }
  assert.equal((await handleEquities(request("intents/" + id + "/preview", { expectedVersion: 0 }), client(), opts)).status, 409);
  const cancelled = await handleEquities(request("intents/" + id + "/cancel", { expectedVersion: 1 }), client(), opts);
  assert.equal(cancelled.status, 200);
  assert.equal((await handleEquities(request("intents/" + id + "/cancel", { expectedVersion: 1 }), client(), opts)).status, 200);
  assert.equal((await handleEquities(request("intents/" + id + "/preview", { expectedVersion: 2 }), client(), opts)).status, 409);
});
Deno.test("concurrent cancel wins over a late provider response and quote is not persisted", async () => {
  const ledger = memoryLedger(), opts = options(ledger);
  await handleEquities(request("intents", fixture.createRequest), client(), opts);
  let signal!: () => void, release!: () => void;
  const started = new Promise<void>(r => { signal = r; }), wait = new Promise<void>(r => { release = r; });
  const quote = opts.previewPorts.quote;
  opts.previewPorts.quote = async (i, q) => { signal(); await wait; return quote(i, q); };
  const inflight = handleEquities(request("intents/" + id + "/preview", { expectedVersion: 0 }), client(), opts);
  await started;
  assert.equal((await handleEquities(request("intents/" + id + "/cancel", { expectedVersion: 0 }), client(), opts)).status, 200);
  release(); assert.equal((await inflight).status, 409);
  const stored = await ledger.get(account, id); assert.equal(stored.state, "cancelled"); assert.equal(stored.preview, null);
});
Deno.test("ledger adapter sends account filters and CAS to RPC, sanitizes provider/database errors", async () => {
  const calls: unknown[] = [], filters: unknown[] = [];
  const c = { rpc: async (name: string, args: unknown) => { calls.push([name, args]); return { data: row(), error: null }; },
    from: () => ({ select: () => ({ eq(k: string, v: string) { filters.push([k, v]); return this; },
      maybeSingle: async () => ({ data: row(), error: null }) }) }) } as unknown as SupabaseClient;
  const ledger = equityLedger(c, () => at);
  await ledger.create(account, owner, fixture.createRequest.clientIntentId, input, "b".repeat(64));
  await ledger.get(account, id); await ledger.change(account, id, owner, 0, "cancel");
  assert.deepEqual(filters, [["account_id", account], ["id", id]]);
  assert.equal((calls[1] as any)[1].p_version, 0); assert.equal((calls[1] as any)[1].p_preview, null);
  for (const message of ["intent_version_conflict", "intent_idempotency_conflict", "wallet_changed", "password=secret"]) {
    const broken = equityLedger({ rpc: async () => ({ data: null, error: { message } }) } as any);
    await assert.rejects(() => broken.create(account, owner, id, input, "b".repeat(64)), (e: any) => {
      assert.equal(e.status, message.includes("secret") ? 503 : 409); assert.equal(e.message.includes("secret"), false); return true;
    });
  }
});
