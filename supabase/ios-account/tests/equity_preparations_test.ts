import { strict as assert } from "node:assert";
import { MarketError } from "../supabase/functions/bsmart-markets/routing.ts";
import { prepareIntent, authorizePreparedIntent, assertStoredPreparation, preparationHash, preparationResponse,
  type PreparationLedger, type PreparationPorts, type PreparationRow } from "../supabase/functions/bsmart-equities/preparations.ts";
import { preparationLedger } from "../supabase/functions/bsmart-equities/preparation_ledger.ts";
import { beginPreparedSigning } from "../supabase/functions/bsmart-equities/preparation_signing.ts";
import { handleEquities } from "../supabase/functions/bsmart-equities/handler.ts";
import { cowTypedData } from "../supabase/functions/bsmart-equities/cow_order.ts";
import { fundingGuard } from "../supabase/functions/bsmart-equities/funding_guard.ts";
import { NETWORKS } from "../supabase/functions/bsmart-equities/assets.ts";
import { at, account, owner, context, signer } from "./fixtures/equity_cow.ts";

const fixture = JSON.parse(await Deno.readTextFile(new URL("../../../contracts/fixtures/evm-equity-preparation.json", import.meta.url)));

async function stored(side: "buy" | "sell" = "buy") {
  const c = await context(side);
  const p: PreparationRow = { intent_id: c.row.id, account_id: account, wallet_address: owner, intent_version: 1,
    network: c.instrument.network, order_uid: c.prepared.orderUid, fingerprint: c.preview.fingerprint,
    preparation_hash: await preparationHash(c.material, c.prepared), material: c.material, prepared: c.prepared,
    expires_at: c.prepared.expiresAt, state: "reserved", signature: null, authorization_hash: null,
    authorized_at: null, created_at: new Date(at).toISOString() };
  return { ...c, p };
}
async function setup(side: "buy" | "sell" = "buy") {
  const c = await stored(side), draft = { ...c.row, state: "draft" as const, version: 0, preview: null, quote_expires_at: null };
  let current = structuredClone(draft) as typeof c.row, persisted: PreparationRow | null = null;
  const calls = { reserve: 0, quote: 0, authorized: 0, signing: 0 };
  const ledger: PreparationLedger = {
    get: async () => structuredClone(persisted),
    reserve: async (row, bound, version, preview, material, prepared, hash) => {
      calls.reserve++;
      if (persisted) {
        if (current.state !== "quoted" || persisted.state !== "reserved" || ![current.version, current.version - 1].includes(version)) throw new MarketError("preparation_conflict", 409);
        return structuredClone(persisted);
      }
      if (version !== current.version || current.state !== "draft") throw new MarketError("intent_version_conflict", 409);
      current = { ...current, state: "quoted", version: version + 1, preview, quote_expires_at: prepared.expiresAt };
      persisted = { ...c.p, account_id: row.account_id, wallet_address: bound, material, prepared,
        network: prepared.instrument.network, intent_version: prepared.intentVersion, expires_at: prepared.expiresAt,
        fingerprint: prepared.fingerprint, order_uid: prepared.orderUid, preparation_hash: hash };
      return structuredClone(persisted);
    },
    authorize: async (p, signature, hash) => {
      calls.authorized++; persisted = { ...p, state: "authorized", signature, authorization_hash: hash, authorized_at: new Date(at).toISOString() };
      current = { ...current, state: "authorized", version: p.intent_version + 1 };
      return structuredClone(persisted);
    },
    startSigning: async p => {
      calls.signing++;
      if (current.state !== "quoted" || current.version !== p.intent_version) throw new MarketError("preparation_conflict", 409);
      persisted = { ...p, state: "signing", signing_started_at: p.signing_started_at ?? new Date(at).toISOString() };
      return structuredClone(persisted);
    },
  };
  const asset = { id: account, symbol: "ASTSx", ticker: "ASTS", name: "ASTS", halted: false, tradingHours: null,
    deployments: [{ network: c.instrument.network, token: c.instrument.token, usdc: c.instrument.usdc, wrapperV2: null }] };
  const ports: PreparationPorts = { ledger, getIntent: async () => structuredClone(current), boundOwner: async () => owner,
    assertIdle: async () => {}, now: () => at, catalogs: { hl: async () => ({ at, values: [] }),
      registry: async () => ({ at, values: [asset] }), asset: async () => ({ at, values: [asset] }) },
    preview: { state: async () => c.state, quote: async () => { calls.quote++; return c.response; } } };
  return { ...c, draft, ports, calls, get current() { return current; }, set current(value: typeof c.row) { current = value; },
    get persisted() { return persisted; }, set persisted(value: PreparationRow | null) { persisted = value; } };
}

Deno.test("private preparation hash survives jsonb key reordering and binds every field", async () => {
  const c = await stored();
  const ordered = Object.fromEntries(Object.entries(c.material).reverse()) as typeof c.material;
  ordered.order = Object.fromEntries(Object.entries(ordered.order).reverse()) as typeof ordered.order;
  assert.equal(await preparationHash(ordered, c.prepared), c.p.preparation_hash);
  assert.notEqual(await preparationHash({ ...c.material, block: "24000001" }, c.prepared), c.p.preparation_hash);
});
Deno.test("stored preparation is account isolated and checks canonical UID, digest and hash", async () => {
  const c = await stored();
  await assertStoredPreparation({ ...c.p, expires_at: c.p.expires_at.replace(".000Z", "+00:00") }, account, account);
  for (const patch of [{ preparation_hash: "a".repeat(64) }, { intent_version: 2 }, { order_uid: "0x" + "ab".repeat(56) },
    { prepared: { ...c.prepared, order: { ...c.prepared.order, buyAmount: "1" } } }]) {
    await assert.rejects(() => assertStoredPreparation({ ...c.p, ...patch }, account, account));
  }
  await assert.rejects(() => assertStoredPreparation(c.p, crypto.randomUUID(), account), (e: any) => e.status === 404);
});
Deno.test("preparation atomically saves fresh quote and reservation without returning signing material", async () => {
  const c = await setup(), response = await prepareIntent(c.draft, 0, c.ports);
  assert.equal(c.current.state, "quoted"); assert.equal(c.current.version, 1); assert.equal(c.calls.reserve, 1);
  assert.equal(response.executionEnabled, false); assert.equal(response.signingEnabled, false);
  const text = JSON.stringify(response);
  for (const privateField of ["material", "prepared", "signature", "orderDigest", "account_id", "domain", "buyToken", "authorization_hash"]) assert.equal(text.includes(privateField), false);
  assert.deepEqual(response, preparationResponse(c.persisted!));
  assert.deepEqual(response, fixture.response);
});
Deno.test("lost-response retry uses immutable stored preparation, never requotes", async () => {
  const c = await setup(), first = await prepareIntent(c.draft, 0, c.ports);
  const quotes = c.calls.quote;
  assert.deepEqual(await prepareIntent(c.current, 0, c.ports), first);
  assert.deepEqual(await prepareIntent(c.current, 1, c.ports), first);
  assert.equal(c.calls.quote, quotes);
  await assert.rejects(() => prepareIntent(c.current, 2, c.ports));
});
Deno.test("preparation compares actual output precision and persists only the selected chain", async () => {
  const c = await setup();
  const asset = { id: account, symbol: "ASTSx", ticker: "ASTS", name: "ASTS", halted: false, tradingHours: null,
    deployments: (["Ethereum", "Ink"] as const).map(network => ({ network, token: c.instrument.token, usdc: NETWORKS[network].usdc, wrapperV2: null })) };
  c.ports.catalogs.registry = c.ports.catalogs.asset = async () => ({ at, values: [asset] });
  c.ports.preview.state = async i => ({ ...c.state, chainId: i.chainId, usdc: i.usdc, tokenDecimals: i.network === "Ink" ? 6 : 18 });
  c.ports.preview.quote = async (i, q) => ({ ...c.response, expiration: new Date(at + (i.network === "Ink" ? 60_000 : 40_000)).toISOString(),
    quote: { ...c.response.quote, ...q, buyAmount: i.network === "Ink" ? "3000000" : "2000000000000000000" } });
  const result = await prepareIntent(c.draft, 0, c.ports);
  assert.equal(result.network, "Ink"); assert.equal(result.expiresAt, new Date(at + 60_000).toISOString());
  assert.equal(c.current.preview!.candidates.length, 1);
  assert.equal(c.current.preview!.candidates[0].instrument.network, "Ink");
});
Deno.test("preparation refuses unfunded, unapproved or unverified quotes without mutation", async () => {
  for (const kind of ["funding", "approval", "verification"]) {
    const c = await setup();
    if (kind === "verification") c.ports.preview.quote = async () => ({ ...c.response, verified: false });
    else c.ports.preview.state = async () => ({ ...c.state, ...(kind === "funding" ? { usdcBalance: "0" } : { usdcAllowance: "0" }) });
    await assert.rejects(() => prepareIntent(c.draft, 0, c.ports), (e: any) => e.code === "funded_approved_quote_required");
    assert.equal(c.calls.reserve, 0); assert.equal(c.persisted, null);
  }
});
Deno.test("preparation blocks changed wallet, active funding, late cancellation and newly listed HL", async () => {
  const changed = await setup(); changed.ports.boundOwner = async () => changed.instrument.token;
  await assert.rejects(() => prepareIntent(changed.draft, 0, changed.ports), (e: any) => e.code === "wallet_changed");
  const busy = await setup(); busy.ports.assertIdle = () => { throw new MarketError("funding_activity_in_progress", 409); };
  await assert.rejects(() => prepareIntent(busy.draft, 0, busy.ports)); assert.equal(busy.calls.quote, 0);
  const cancelled = await setup(); cancelled.ports.preview.quote = async () => {
    cancelled.current = { ...cancelled.current, state: "cancelled", version: 1 }; return cancelled.response;
  };
  await assert.rejects(() => prepareIntent(cancelled.draft, 0, cancelled.ports)); assert.equal(cancelled.calls.reserve, 0);
  const listed = await setup(); let n = 0;
  listed.ports.catalogs.hl = async () => ({ at, values: ++n > 1 ? [{ coin: "xyz:ASTS", symbol: "ASTS", dex: "xyz", collateralToken: 0, active: true }] : [] } as any);
  await assert.rejects(() => prepareIntent(listed.draft, 0, listed.ports)); assert.equal(listed.calls.reserve, 0);
});
Deno.test("released or authorized preparations cannot be regenerated into another reservation", async () => {
  for (const state of ["released", "signing", "authorized"] as const) {
    const c = await setup(); c.persisted = { ...c.p, state }; c.current = c.row;
    await assert.rejects(() => prepareIntent(c.current, 1, c.ports)); assert.equal(c.calls.quote, 0);
  }
});
Deno.test("internal authorization verifies owner signature against fresh private preparation", async () => {
  const c = await setup(); c.persisted = c.p; c.current = c.row;
  await beginPreparedSigning(account, account, 1, c.ports);
  const typed = cowTypedData(c.prepared), signature = await signer.signTypedData({ ...typed, domain: typed.domain as any });
  const result = await authorizePreparedIntent(account, account, 1, signature, c.ports);
  assert.equal(result.state, "authorized"); assert.equal(c.calls.authorized, 1);
  assert.equal(result.signature, signature.toLowerCase()); assert.match(result.authorization_hash!, /^[a-f0-9]{64}$/);
});
Deno.test("internal authorization refuses invalid signature, late allowance loss and sell return gap", async () => {
  const c = await setup(); c.persisted = c.p; c.current = c.row;
  await beginPreparedSigning(account, account, 1, c.ports);
  await assert.rejects(() => authorizePreparedIntent(account, account, 1, "0x1234", c.ports));
  const typed = cowTypedData(c.prepared), signature = await signer.signTypedData({ ...typed, domain: typed.domain as any });
  c.ports.preview.state = async () => ({ ...c.state, usdcAllowance: "0" });
  await assert.rejects(() => authorizePreparedIntent(account, account, 1, signature, c.ports)); assert.equal(c.calls.authorized, 0);
  const sell = await setup("sell"); sell.persisted = sell.p; sell.current = sell.row;
  await assert.rejects(() => authorizePreparedIntent(account, account, 1, signature, sell.ports), (e: any) => e.code === "return_authorization_unavailable");
});
Deno.test("accepted authorization replays identical consent without refreshing or resigning an expired order", async () => {
  const c = await setup(); c.persisted = c.p; c.current = c.row;
  await beginPreparedSigning(account, account, 1, c.ports);
  const typed = cowTypedData(c.prepared), signature = await signer.signTypedData({ ...typed, domain: typed.domain as any });
  const first = await authorizePreparedIntent(account, account, 1, signature, c.ports);
  c.ports.now = () => at + 600_000;
  c.ports.preview.state = c.ports.catalogs.hl = async () => { throw Error("unexpected_provider_call"); };
  assert.deepEqual(await authorizePreparedIntent(account, account, 1, signature, c.ports), first);
  await assert.rejects(() => authorizePreparedIntent(account, account, 1, "0x" + "ab".repeat(65), c.ports));
});
Deno.test("private ledger filters accounts, passes CAS and hides database error details", async () => {
  const c = await stored(), calls: any[] = [], filters: any[] = [];
  const ledger = preparationLedger({ rpc: async (name: string, args: any) => { calls.push([name, args]); return { data: c.p, error: null }; },
    from: () => ({ select: () => ({ eq(k: string, v: string) { filters.push([k, v]); return this; },
      maybeSingle: async () => ({ data: c.p, error: null }) }) }) } as any);
  await ledger.get(account, account);
  await ledger.reserve(c.row, owner, 0, c.row.preview!, c.material, c.prepared, c.p.preparation_hash);
  assert.deepEqual(filters, [["account_id", account], ["intent_id", account]]);
  assert.equal(calls[0][0], "bsmart_equity_prepare"); assert.equal(calls[0][1].p_version, 0);
  for (const message of ["wallet_activity_in_progress", "password=secret"]) {
    const broken = preparationLedger({ rpc: async () => ({ data: null, error: { message } }) } as any);
    await assert.rejects(() => broken.reserve(c.row, owner, 0, c.row.preview!, c.material, c.prepared, c.p.preparation_hash),
      (e: any) => e.status === (message.includes("secret") ? 503 : 409) && !e.message.includes("secret"));
  }
});
Deno.test("preparation HTTP is gated and has no signing or authorization endpoint", async () => {
  const c = await setup(), client = { auth: { getUser: async () => ({ data: { user: { id: account, identities: [{ provider: "apple" }] } } }) },
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { address: owner } }) }) }) }) } as any;
  const options = { catalogs: c.ports.catalogs, discoveryEnabled: true, ledgerEnabled: true,
    ledger: { get: c.ports.getIntent } as any, preparationLedger: c.ports.ledger, previewEnabled: true, previewPorts: c.ports.preview,
    fundingPorts: { assertIdle: c.ports.assertIdle } as any, now: c.ports.now };
  const request = (action: string, body: unknown = { expectedVersion: 0 }) => new Request(`https://test.invalid/bsmart-equities/intents/${account}/${action}`,
    { method: "POST", headers: { authorization: "Bearer a.b.c", "content-type": "application/json" }, body: JSON.stringify(body) });
  assert.equal((await handleEquities(request("prepare"), client, options)).status, 503);
  const enabled = { ...options, preparationEnabled: true };
  assert.equal((await handleEquities(request("prepare", { expectedVersion: 0, chain: "Ink" }), client, enabled)).status, 422);
  assert.equal((await handleEquities(request("prepare"), client, enabled)).status, 200);
  for (const action of ["authorize", "sign", "signing-start", "submit"]) assert.equal((await handleEquities(request(action), client, enabled)).status, 404);
});
Deno.test("funding guard optionally includes unsigned and authorized wallet reservations", async () => {
  const queries: string[] = [];
  const client = { from: (table: string) => {
    queries.push(table);
    const q = { select: () => q, eq: () => q, neq: () => q, in: () => q,
      limit: () => Promise.resolve({ data: table === "bsmart_equity_preparations" ? [{ intent_id: "private" }] : [], error: null }) };
    return q;
  } } as any;
  await assert.rejects(() => fundingGuard(client, true)(account, owner, account), (e: any) => e.code === "funding_activity_in_progress");
  assert.equal(queries.at(-1), "bsmart_equity_preparations");
});

Deno.test("signing payload is returned only after durable exposure; retries preserve the same order", async () => {
  const c = await setup(); c.persisted = c.p; c.current = c.row;
  const first = await beginPreparedSigning(account, account, 1, c.ports);
  assert.equal(c.persisted!.state, "signing"); assert.equal(c.calls.signing, 1);
  assert.equal(first.executionEnabled, false); assert.deepEqual(first.prepared, c.prepared);
  assert.deepEqual(await beginPreparedSigning(account, account, 1, c.ports), first);
  assert.equal(c.calls.quote, 0);
  for (const key of ["material", "signature", "authorization_hash"]) assert.equal(Object.hasOwn(first, key), false);
});
Deno.test("signing exposure checks fresh funds, owner, version, HL and sell consent before mutation", async () => {
  for (const kind of ["funds", "owner", "version", "hl", "sell"]) {
    const c = await setup(kind === "sell" ? "sell" : "buy"); c.persisted = c.p; c.current = c.row;
    if (kind === "funds") c.ports.preview.state = async () => ({ ...c.state, usdcBalance: "0" });
    if (kind === "owner") c.ports.boundOwner = async () => c.instrument.token;
    if (kind === "hl") c.ports.catalogs.hl = async () => ({ at, values: [{ coin: "xyz:ASTS", symbol: "ASTS", dex: "xyz", collateralToken: 0, active: true }] } as any);
    await assert.rejects(() => beginPreparedSigning(account, account, kind === "version" ? 2 : 1, c.ports));
    assert.equal(c.calls.signing, 0); assert.equal(c.persisted.state, "reserved");
  }
});
Deno.test("lost exposure response or DB failure never returns material or releases the held reservation", async () => {
  const c = await setup(); c.persisted = c.p; c.current = c.row;
  const start = c.ports.ledger.startSigning;
  c.ports.ledger.startSigning = async p => { await start(p); throw new MarketError("preparation_ledger_unavailable"); };
  await assert.rejects(() => beginPreparedSigning(account, account, 1, c.ports));
  assert.equal(c.persisted!.state, "signing");
  c.ports.ledger.startSigning = start;
  c.ports.now = () => at + 60_000;
  await assert.rejects(() => beginPreparedSigning(account, account, 1, c.ports));
  assert.equal(c.persisted!.state, "signing"); assert.equal(c.calls.quote, 0);
});
Deno.test("signature acceptance cannot skip the persisted signing-start boundary", async () => {
  const c = await setup(); c.persisted = c.p; c.current = c.row;
  const typed = cowTypedData(c.prepared), signature = await signer.signTypedData({ ...typed, domain: typed.domain as any });
  await assert.rejects(() => authorizePreparedIntent(account, account, 1, signature, c.ports), (e: any) => e.code === "preparation_conflict");
  assert.equal(c.calls.authorized, 0);
});
