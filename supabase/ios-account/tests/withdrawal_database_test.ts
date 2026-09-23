import { strict as assert } from "node:assert";
import { PGlite } from "npm:@electric-sql/pglite@0.5.8";

Deno.test("withdrawal migration serializes wallet submissions and isolates records", async () => {
  const db = new PGlite();
  const account = "00000000-0000-0000-0000-000000000001";
  const wallet = "0x" + "1".repeat(40);
  const recipient = "0x" + "2".repeat(40);
  const ids = [
    "00000000-0000-0000-0000-000000000011",
    "00000000-0000-0000-0000-000000000012",
    "00000000-0000-0000-0000-000000000013",
  ];
  try {
    await db.exec(`
      create role anon;
      create role authenticated;
      create role service_role bypassrls;
      create schema auth;
      create table auth.users(id uuid primary key);
      insert into auth.users values ('${account}');
      create table public.bsmart_wallets(account_id uuid primary key, address text not null);
      insert into public.bsmart_wallets values ('${account}', '${wallet}');
    `);
    const migration = await Deno.readTextFile(
      new URL(
        "../supabase/migrations/202609230002_withdrawal_coordinator.sql",
        import.meta.url,
      ),
    );
    await db.exec(migration);
    await db.exec("set role service_role");

    let nonce = Date.now();
    const reserve = async (id: string) => {
      nonce += 1;
      const result = await db.query<{ value: { state: string } }>(
        "select to_json(public.bsmart_withdrawal_reserve($1,$2,$3,$4,$5,$6,$7)) as value",
        [account, id, wallet, recipient, "10", "", nonce],
      );
      return result.rows[0].value;
    };
    assert.equal((await reserve(ids[0])).state, "reserved");
    await assert.rejects(() => reserve(ids[1]), /withdrawal_pending/);
    await db.query(
      "update public.bsmart_withdrawals set expires_at = now() - interval '1 second' where id = $1",
      [ids[0]],
    );
    assert.equal((await reserve(ids[1])).state, "reserved");
    assert.equal(
      (await db.query<{ state: string }>(
        "select state from public.bsmart_withdrawals where id = $1",
        [ids[0]],
      )).rows[0].state,
      "expired",
    );

    const transition = async (id: string, from: string, to: string) =>
      db.query<{ state: string }>(
        "select (public.bsmart_withdrawal_transition($1,$2,$3,$4)).state as state",
        [account, id, from, to],
      );
    assert.equal(
      (await transition(ids[1], "reserved", "submitting")).rows[0].state,
      "submitting",
    );
    await assert.rejects(() => transition(ids[1], "reserved", "submitting"));
    await assert.rejects(() => reserve(ids[2]), /withdrawal_pending/);
    assert.equal(
      (await transition(ids[1], "submitting", "accepted")).rows[0].state,
      "accepted",
    );
    assert.equal((await reserve(ids[2])).state, "reserved");

    await db.exec("reset role; set role authenticated");
    await assert.rejects(() =>
      db.query("select * from public.bsmart_withdrawals")
    );
    await assert.rejects(() => reserve("00000000-0000-0000-0000-000000000014"));
    await db.exec("reset role");
    await db.query("delete from auth.users where id = $1", [account]);
    assert.equal(
      (await db.query<{ count: number }>(
        "select count(*)::int as count from public.bsmart_withdrawals",
      )).rows[0].count,
      0,
    );
  } finally {
    await db.close();
  }
});
