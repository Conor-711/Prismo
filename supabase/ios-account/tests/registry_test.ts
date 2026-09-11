import { strict as assert } from "node:assert";
import { PGlite } from "npm:@electric-sql/pglite@0.5.8";

Deno.test("wallet migration enforces RLS, role grants, immutable ownership and one-time proof consumption", async () => {
  // Disposable in-memory Postgres only. No user database or network credentials.
  const db = new PGlite();
  try {
    await db.exec(`
      create role anon;
      create role authenticated;
      create role service_role bypassrls;
      create schema auth;
      create table auth.users(id uuid primary key);
      create function auth.uid() returns uuid language sql stable as
        $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
      grant usage on schema auth to authenticated;
      grant execute on function auth.uid() to authenticated;
      insert into auth.users values
        ('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002');
    `);
    const sql = await Deno.readTextFile(new URL("../supabase/migrations/202609120001_wallet_registry.sql", import.meta.url));
    await db.exec(sql);
    const account = "00000000-0000-0000-0000-000000000001";
    const other = "00000000-0000-0000-0000-000000000002";
    const address = "0x" + "1".repeat(40), hash = "a".repeat(64);
    await db.exec("set role service_role");
    const create = async (id: string, target = address) => {
      const result = await db.query<{ proof: { id: string; accountId: string } }>(
        "select public.bsmart_wallet_challenge($1,$2,$3,$4) as proof", [id, hash, target, "b".repeat(64)]);
      return result.rows[0].proof;
    };
    const challenge = await create(account);
    await assert.rejects(() => db.query("select public.bsmart_wallet_commit($1,$2,$3)", [other, hash, challenge.id]));
    await assert.rejects(() => db.query("select public.bsmart_wallet_commit($1,$2,$3)", [account, "c".repeat(64), challenge.id]));
    await db.query("select public.bsmart_wallet_commit($1,$2,$3)", [account, hash, challenge.id]);
    await assert.rejects(() => db.query("select public.bsmart_wallet_commit($1,$2,$3)", [account, hash, challenge.id]));
    await assert.rejects(() => create(account, "0x" + "2".repeat(40)));
    const otherChallenge = await create(other);
    await assert.rejects(() => db.query("select public.bsmart_wallet_commit($1,$2,$3)", [other, hash, otherChallenge.id]));
    await db.exec("reset role; set role authenticated");
    await db.query("select set_config('request.jwt.claim.sub', $1, false)", [account]);
    assert.equal((await db.query("select * from public.bsmart_wallets")).rows.length, 1);
    await db.query("select set_config('request.jwt.claim.sub', $1, false)", [other]);
    assert.equal((await db.query("select * from public.bsmart_wallets")).rows.length, 0);
    for (const query of [
      "select * from bsmart_private.wallet_challenges",
      "delete from public.bsmart_wallets",
      "update public.bsmart_wallets set address = '0x" + "3".repeat(40) + "'",
      "insert into public.bsmart_wallets(account_id,address) values ('" + other + "','0x" + "3".repeat(40) + "')",
      "select public.bsmart_wallet_commit('" + account + "','" + hash + "','" + challenge.id + "')",
      "select public.bsmart_wallet_challenge_read('" + account + "','" + hash + "','" + challenge.id + "')",
    ]) await assert.rejects(() => db.exec(query));
    await db.exec("reset role; set role anon");
    await assert.rejects(() => db.exec("select * from public.bsmart_wallets"));
  } finally { await db.close(); }
});
