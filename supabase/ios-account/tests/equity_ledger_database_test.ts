import { strict as assert } from "node:assert";

// Source-level guards only: this suite does not execute DDL or claim PostgreSQL/RLS acceptance.
const sql = await Deno.readTextFile(new URL("../supabase/migrations/202610010005_equity_intent_ledger.sql", import.meta.url));
Deno.test("equity migration restricts mutation RPCs to service and reads to account RLS", () => {
  for (const table of ["intents", "legs"]) {
    assert.match(sql, new RegExp(`alter table public.bsmart_equity_${table} enable row level security`));
    assert.match(sql, new RegExp(`create policy bsmart_equity_${table}_owner_read[\\s\\S]*?using\\(account_id=\\(select auth.uid\\(\\)\\)\\)`));
  }
  assert.match(sql, /revoke all[\s\S]*from public,anon,authenticated/);
  assert.match(sql, /grant select\(id,intent_id,account_id,kind,leg_index,source_network,destination_network,state,provider,provider_id,attempts,checked_at\)/);
  assert.equal(/grant (?:all|insert|update|delete).*to authenticated/.test(sql), false);
  assert.match(sql, /unique\(account_id,client_intent_id\)/);
  assert.match(sql, /r\.request_hash<>p_hash or r\.input<>p_input/);
  assert.match(sql, /pg_advisory_xact_lock/);
});
Deno.test("equity migration uses locked CAS, forbids post-execution cancellation and false freshness", () => {
  assert.match(sql, /where id=p_id and account_id=p_account for update/);
  assert.match(sql, /if r\.version<>p_version then raise exception 'intent_version_conflict'/);
  assert.match(sql, /if r\.state not in \('draft','quoted'\)/);
  assert.match(sql, /observed<=t-interval '30 seconds'/);
  assert.match(sql, /expires<=t\+interval '5 seconds'/);
  assert.equal(/create function public\.bsmart_equity_(?:authorize|submit|transfer)/.test(sql), false);
});
Deno.test("equity legs have one permanent attempt, deterministic provider identity and no lease reclamation", () => {
  assert.match(sql, /attempts between 0 and 1/); assert.match(sql, /unique\(provider,source_network,provider_id\)/);
  assert.match(sql, /unique\(intent_id,kind,leg_index\)/); assert.match(sql, /if l\.state<>'reserved' or l\.attempts<>0/);
  assert.match(sql, /lease_id=gen_random_uuid\(\),leased_until=t\+interval '60 seconds'/);
  assert.equal(/set[\s\S]{0,60}attempts=0/.test(sql), false);
  assert.match(sql, /'unknown','confirmed','failed'/);
  assert.match(sql, /state not in \('confirmed','failed'\) or \(evidence_hash is not null/);
  assert.match(sql, /leg_dependency_pending/);
  assert.match(sql, /and kind='order' and state='confirmed'/);
  assert.match(sql, /destination_network=l\.source_network/);
});
