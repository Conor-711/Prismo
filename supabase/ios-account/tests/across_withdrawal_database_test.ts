import { strict as assert } from "node:assert";
import { PGlite } from "npm:@electric-sql/pglite@0.5.8";

Deno.test("Across reservations exclude overlapping legacy and Across withdrawals", async () => {
  const db = new PGlite();
  const account = "00000000-0000-0000-0000-000000000001";
  const wallet = "0x" + "1".repeat(40);
  const recipient = "0x" + "2".repeat(40);
  try {
    await db.exec(`
      create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth; create table auth.users(id uuid primary key);
      insert into auth.users values ('${account}');
      create table public.bsmart_wallets(account_id uuid primary key, address text not null);
      insert into public.bsmart_wallets values ('${account}', '${wallet}');
    `);
    for (const name of ["202609230002_withdrawal_coordinator.sql", "202609230005_across_withdrawals.sql"]) {
      await db.exec(await Deno.readTextFile(new URL(`../supabase/migrations/${name}`, import.meta.url)));
    }
    await db.exec("set role service_role");
    const reserve = (id: string) => db.query<{ state: string }>(
      "select (public.bsmart_across_withdrawal_reserve($1,$2,$3,$4,$5,$6,$7,$8,$9)).state as state",
      [account, id, wallet, recipient, "perps", "100000000", "{}",
        new Date(Date.now() + 90_000).toISOString(), String(BigInt("0x" + id.replaceAll("-", "")))],
    );
    const first = crypto.randomUUID(), second = crypto.randomUUID();
    assert.equal((await reserve(first)).rows[0].state, "quoted");
    await assert.rejects(() => reserve(second), /withdrawal_pending/);
    await db.query("update public.bsmart_across_withdrawals set quote_expires_at = now() - interval '1 second' where id = $1", [first]);
    assert.equal((await reserve(second)).rows[0].state, "quoted");
    const expired = await db.query<{ state: string }>("select state from public.bsmart_across_withdrawals where id = $1", [first]);
    assert.equal(expired.rows[0].state, "quote_expired");
    await db.query("update public.bsmart_across_withdrawals set state = 'submitted' where id = $1", [second]);
    await assert.rejects(() => reserve(crypto.randomUUID()), /withdrawal_pending/);
    await db.query("update public.bsmart_across_withdrawals set state = 'filled' where id = $1", [second]);
    assert.equal((await reserve(crypto.randomUUID())).rows[0].state, "quoted");
    await db.exec("reset role; set role authenticated");
    await assert.rejects(() => db.query("select * from public.bsmart_across_withdrawals"));
  } finally { await db.close(); }
});
