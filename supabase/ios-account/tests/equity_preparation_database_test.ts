import { strict as assert } from "node:assert";
import { PGlite } from "npm:@electric-sql/pglite@0.5.8";
import { at, account, owner, context } from "./fixtures/equity_cow.ts";
import { prepareCowOrder } from "../supabase/functions/bsmart-equities/cow_order.ts";
import { preparationHash } from "../supabase/functions/bsmart-equities/preparations.ts";
import type { IntentRow } from "../supabase/functions/bsmart-equities/intents.ts";

// Isolated in-memory SQL fixtures only; never connects to a user database or
// creates real accounts. PGlite is single-session, not a concurrent lock proof.
async function database() {
  const db = new PGlite(), root = new URL("../supabase/migrations/", import.meta.url);
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql as $$ select null::uuid $$;
    create table public.bsmart_wallets(account_id uuid primary key references auth.users(id),address text unique not null);
    create table public.test_clock(at timestamptz not null);
    insert into public.test_clock values('2026-10-01T00:00:00Z');
    create function public.test_now() returns timestamptz language sql as $$ select at from public.test_clock $$;
    grant select on public.bsmart_wallets to service_role;`);
  for (const file of ["202609230002_withdrawal_coordinator.sql", "202609230005_across_withdrawals.sql",
    "202610010005_equity_intent_ledger.sql", "202610010006_equity_preparations.sql", "202610010007_equity_signing_exposure.sql"]) {
    await db.exec((await Deno.readTextFile(new URL(file, root))).replaceAll("clock_timestamp()", "public.test_now()"));
  }
  await db.query("insert into auth.users values($1)", [account]);
  await db.query("insert into public.bsmart_wallets values($1,$2)", [account, owner]);
  await db.exec("set role service_role");
  const value = async (expression: string, args: unknown[] = []) =>
    (await db.query<{ value: any }>(`select to_jsonb(${expression}) as value`, args)).rows[0].value;
  const c = await context();
  const draft = async () => await value("public.bsmart_equity_intent_create($1,$2,$3,$4,$5)",
    [account, owner, crypto.randomUUID(), c.input, "a".repeat(64)]) as IntentRow;
  const argumentsFor = async (row: IntentRow) => {
    const quoted: IntentRow = { ...row, state: "quoted", version: row.version + 1, preview: c.row.preview, quote_expires_at: c.preview.expiresAt };
    const prepared = await prepareCowOrder(c.material, quoted, quoted.version, c.state, at, owner);
    return [account, row.id, owner, row.version, c.row.preview, c.material, prepared, await preparationHash(c.material, prepared)];
  };
  const reserve = async (args: unknown[]) => value("public.bsmart_equity_prepare($1,$2,$3,$4,$5,$6,$7,$8)", args);
  const withdrawal = async () => value("public.bsmart_withdrawal_reserve($1,$2,$3,$3,'1','',$4)",
    [account, crypto.randomUUID(), owner, at]);
  const across = async () => value("public.bsmart_across_withdrawal_reserve($1,$2,$3,$3,'perps',1000000,'{}',$4,$5)",
    [account, crypto.randomUUID(), owner, new Date(at + 60_000).toISOString(), String(Math.floor(Math.random() * 1000000))]);
  return { db, value, draft, argumentsFor, reserve, withdrawal, across };
}

Deno.test("preparation SQL is private, immutable, CAS-bound and cancelled atomically", async () => {
  const d = await database();
  try {
    const r = await d.draft(), args = await d.argumentsFor(r), p = await d.reserve(args);
    assert.equal(p.intent_version, 1); assert.equal(p.state, "reserved");
    assert.equal((await d.value("(select version from public.bsmart_equity_intents where id=$1)", [r.id])), 1);
    assert.deepEqual(await d.reserve(args), p);
    await assert.rejects(() => d.reserve([args[0], args[1], args[2], 3, ...args.slice(4)]), /intent_version_conflict/);
    await assert.rejects(() => d.db.query("update public.bsmart_equity_preparations set state='released'"), /permission denied/);
    await assert.rejects(() => d.value("public.bsmart_equity_intent_change($1,$2,$3,1,'quote',$4)", [account, r.id, owner, args[4]]), /preparation_conflict/);
    for (const role of ["anon", "authenticated"]) {
      await d.db.exec(`reset role; set role ${role}`);
      await assert.rejects(() => d.db.query("select * from public.bsmart_equity_preparations"), /permission denied/);
      await assert.rejects(() => d.reserve(args), /permission denied/);
    }
    await d.db.exec("reset role; set role service_role");
    const cancelled = await d.value("public.bsmart_equity_intent_change($1,$2,$3,1,'cancel')", [account, r.id, owner]);
    assert.equal(cancelled.state, "cancelled");
    assert.equal(await d.value("(select state from public.bsmart_equity_preparations where intent_id=$1)", [r.id]), "released");
    await assert.rejects(() => d.reserve(args), /preparation_conflict/);
    assert.equal((await d.withdrawal()).state, "reserved");
  } finally { await d.db.close(); }
});
Deno.test("SQL wallet exclusion works in both directions for HL, Across and equity", async () => {
  const d = await database();
  try {
    const r = await d.draft(), args = await d.argumentsFor(r);
    const w = await d.withdrawal();
    await assert.rejects(() => d.reserve(args), /wallet_activity_in_progress/);
    // Failed reserve rolls back its nested quote/version, not just the private row.
    assert.equal(await d.value("(select version from public.bsmart_equity_intents where id=$1)", [r.id]), 0);
    assert.equal(await d.value("(select count(*) from public.bsmart_equity_preparations)"), 0);
    await assert.rejects(() => d.across(), /withdrawal_pending/);
    await d.value("public.bsmart_withdrawal_transition($1,$2,'reserved','cancelled')", [account, w.id]);
    const a = await d.across();
    await assert.rejects(() => d.withdrawal(), /wallet_activity_in_progress/);
    await assert.rejects(() => d.reserve(args), /wallet_activity_in_progress/);
    await d.db.query("update public.bsmart_across_withdrawals set state='cancelled' where id=$1", [a.id]);
    await d.reserve(args);
    await assert.rejects(() => d.withdrawal(), /wallet_activity_in_progress/);
    await assert.rejects(() => d.across(), /wallet_activity_in_progress/);
    const second = await d.draft();
    await assert.rejects(async () => d.reserve(await d.argumentsFor(second)), /wallet_activity_in_progress/);
  } finally { await d.db.close(); }
});
Deno.test("expiry never releases reservation; exact UID is permanently deduplicated", async () => {
  const d = await database();
  try {
    const r = await d.draft(), args = await d.argumentsFor(r); await d.reserve(args);
    await d.db.exec("reset role; update public.test_clock set at=at+interval '61 seconds'; set role service_role");
    await assert.rejects(() => d.reserve(args), /quote_expired/);
    await assert.rejects(() => d.across(), /wallet_activity_in_progress|invalid_across_quote/);
    assert.equal(await d.value("(select state from public.bsmart_equity_preparations where intent_id=$1)", [r.id]), "reserved");
    await d.value("public.bsmart_equity_intent_change($1,$2,$3,1,'cancel')", [account, r.id, owner]);
    await d.db.exec("reset role; update public.test_clock set at=at-interval '61 seconds'; set role service_role");
    const second = await d.draft(), nextArgs = await d.argumentsFor(second);
    await assert.rejects(() => d.reserve(nextArgs), /duplicate key/);
    assert.equal(await d.value("(select version from public.bsmart_equity_intents where id=$1)", [second.id]), 0);
  } finally { await d.db.close(); }
});
Deno.test("service authorization installs exactly one inert leg and never enables execution or cancellation", async () => {
  const d = await database();
  try {
    const r = await d.draft(), args = await d.argumentsFor(r), p = await d.reserve(args);
    // Synthetic SQL boundary signature, not crypto validation or real signing.
    await d.value("public.bsmart_equity_signing_start($1,$2,$3,1,$4)", [account, r.id, owner, p.preparation_hash]);
    const params = [account, r.id, owner, 1, p.preparation_hash, "0x" + "ab".repeat(65), "b".repeat(64)];
    const auth = () => d.value("public.bsmart_equity_authorize_prepared($1,$2,$3,$4,$5,$6,$7)", params);
    assert.equal((await auth()).state, "authorized"); assert.equal((await auth()).state, "authorized");
    const leg = await d.value("(select to_jsonb(l) from public.bsmart_equity_legs l where intent_id=$1)", [r.id]);
    assert.equal(leg.state, "reserved"); assert.equal(leg.attempts, 0);
    assert.equal(await d.value("(select count(*) from public.bsmart_equity_legs)"), 1);
    await assert.rejects(() => d.value("public.bsmart_equity_intent_change($1,$2,$3,2,'cancel')", [account, r.id, owner]), /intent_state_conflict/);
    await assert.rejects(() => d.value("public.bsmart_equity_leg_claim($1,0)", [leg.id]), /intent_state_conflict/);
    await assert.rejects(() => d.withdrawal(), /wallet_activity_in_progress/);
    await d.db.exec("reset role");
    await assert.rejects(() => d.db.query("update public.bsmart_equity_intents set state='order_pending',version=version+1 where id=$1", [r.id]), /preparation_conflict/);
    await assert.rejects(() => d.db.query("update public.bsmart_equity_legs set state='submitting',attempts=1,lease_id=gen_random_uuid(),leased_until=public.test_now() where id=$1", [leg.id]), /equity_execution_disabled/);
  } finally { await d.db.close(); }
});

Deno.test("SQL signing exposure is immutable and cannot cancel, refresh, release or expire automatically", async () => {
  const d = await database();
  try {
    const r = await d.draft(), args = await d.argumentsFor(r), p = await d.reserve(args);
    const params = [account, r.id, owner, 1, p.preparation_hash];
    const auth = "public.bsmart_equity_authorize_prepared($1,$2,$3,$4,$5,$6,$7)";
    await assert.rejects(() => d.value(auth, [...params, "0x" + "ab".repeat(65), "b".repeat(64)]), /preparation_conflict/);
    const start = "public.bsmart_equity_signing_start($1,$2,$3,$4,$5)";
    const first = await d.value(start, params);
    assert.equal(first.state, "signing"); assert.equal(Date.parse(first.signing_started_at), at);
    assert.deepEqual(await d.value(start, params), first);
    await assert.rejects(() => d.value(start, [account, r.id, owner, 2, p.preparation_hash]), /preparation_conflict/);
    await assert.rejects(() => d.value(start, [crypto.randomUUID(), r.id, owner, 1, p.preparation_hash]), /intent_not_found/);
    await assert.rejects(() => d.value("public.bsmart_equity_intent_change($1,$2,$3,1,'cancel')", [account, r.id, owner]), /preparation_conflict/);
    await assert.rejects(() => d.reserve(args), /preparation_conflict/);
    await assert.rejects(() => d.withdrawal(), /wallet_activity_in_progress/);
    await assert.rejects(() => d.across(), /wallet_activity_in_progress/);
    await d.db.exec("reset role");
    await assert.rejects(() => d.db.query("update public.bsmart_equity_preparations set state='released',signing_started_at=null"), /preparation_conflict/);
    await d.db.exec("update public.test_clock set at=at+interval '61 seconds'; set role service_role");
    await assert.rejects(() => d.value(start, params), /quote_expired/);
    assert.equal(await d.value("(select state from public.bsmart_equity_preparations where intent_id=$1)", [r.id]), "signing");
    for (const role of ["anon", "authenticated"]) {
      await d.db.exec(`reset role; set role ${role}`);
      await assert.rejects(() => d.value(start, params), /permission denied/);
    }
  } finally { await d.db.close(); }
});
