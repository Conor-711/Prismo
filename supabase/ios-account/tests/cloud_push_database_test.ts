import { strict as assert } from "node:assert";
import { PGlite } from "npm:@electric-sql/pglite@0.5.8";

Deno.test("cloud push SQL isolates credentials, production consent and at-most-once slot claims", async () => {
  const db = new PGlite();
  const root = new URL("../supabase/migrations/", import.meta.url);
  try {
    // Hosted extensions are stubbed only here; all delivery/permission SQL is real.
    await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth; create table auth.users(id uuid primary key);
      create table public.bsmart_content_releases(revision text primary key);
      create schema extensions; create schema vault; create schema cron; create schema net;
      create function extensions.gen_random_bytes(integer) returns bytea language sql as
        $$ select decode(repeat('ab',$1),'hex') $$;
      create function extensions.digest(text,text) returns bytea language sql as
        $$ select convert_to($1,'UTF8') $$;
      create table vault.secrets(name text unique,secret text);
      create view vault.decrypted_secrets as select name,secret as decrypted_secret from vault.secrets;
      create function vault.create_secret(text,text) returns uuid language plpgsql as $$ begin
        insert into vault.secrets values($2,$1); return gen_random_uuid(); end $$;
      create function net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds integer)
        returns bigint language sql as $$ select 1::bigint $$;
      create table cron.job(jobname text primary key,schedule text,command text);
      create function cron.schedule(text,text,text) returns bigint language plpgsql as $$ begin
        insert into cron.job values($1,$2,$3) on conflict(jobname) do update
          set schedule=excluded.schedule,command=excluded.command; return 1; end $$;
      create table public.test_clock(at timestamptz);
      insert into public.test_clock values('2026-10-01T10:01:00Z');
      create function public.test_now() returns timestamptz language sql as $$ select at from public.test_clock $$;`);
    for (const file of ["202609160001_content_notifications.sql", "202609230001_interest_push.sql",
      "202610010001_cloud_push_dispatch.sql"]) {
      const source = await Deno.readTextFile(new URL(file, root));
      await db.exec(source.replaceAll("now()", "public.test_now()"));
    }
    const scalar = async <T>(sql: string, params: unknown[] = []) =>
      (await db.query<{ value: T }>(`select ${sql} as value`, params)).rows[0].value;
    assert.equal(await scalar<boolean>("public.bsmart_push_worker_authorized($1)", ["ab".repeat(32)]), true);
    assert.equal(await scalar<boolean>("public.bsmart_push_worker_authorized($1)", ["cd".repeat(32)]), false);
    assert.equal((await db.query<any>("select * from cron.job")).rows[0].schedule, "0-29 0,10,14 * * *");
    const user = crypto.randomUUID(), sandboxUser = crypto.randomUUID();
    await db.query("insert into auth.users values($1),($2)", [user, sandboxUser]);
    const device = crypto.randomUUID(), sandbox = crypto.randomUUID();
    await db.query(`insert into public.bsmart_push_devices
      (id,installation_id,user_id,apns_token,environment,locale,followed_author_ids,updated_at)
      values($1,$2,$3,$4,'production','zh-Hans',array['x:alice'],public.test_now()),
        ($5,$6,$7,$8,'development','en',array['x:alice'],public.test_now())`,
      [device, crypto.randomUUID(), user, "a".repeat(64), sandbox, crypto.randomUUID(), sandboxUser, "b".repeat(64)]);
    const event = async (owner: string, actor = "x:alice", kind = "opinion") => db.query(`
      insert into public.bsmart_interest_push_events(user_id,event_kind,event_id,actor_id,ticker,actor_name,created_at)
      values($1,$2,$3,$4,'NVDA','Alice',public.test_now()-interval '2 minutes')`,
      [owner, kind, crypto.randomUUID(), actor]);
    await event(user); await event(user); await event(sandboxUser); await event(user, "wallet", "movement");
    assert.equal(await scalar<number>("public.bsmart_push_prepare_slot()"), 1);
    assert.equal(await scalar<number>("public.bsmart_push_prepare_slot()"), 0);
    const delivery = await scalar<any>("public.bsmart_push_claim()");
    assert.equal(delivery.user_id, user); assert.equal(delivery.item_count, 2);
    assert.equal(delivery.environment, "production");
    assert.equal(await scalar("public.bsmart_push_claim()"), null, "Uncertain sends cannot be reclaimed");
    const finish = (d: any, status: number | null, invalid = false) => scalar<boolean>(
      "public.bsmart_push_complete($1,$2,$3,$4,$5,$6)",
      [d.user_id, d.slot_at, d.apns_id, status, invalid, d.device_updated_at]);
    assert.equal(await finish(delivery, 200), true);
    assert.equal(await finish(delivery, 200), false);
    await event(user);
    assert.equal(await scalar<number>("public.bsmart_push_prepare_slot()"), 0, "No second digest in same slot");
    await db.exec("update public.test_clock set at='2026-10-01T10:31:00Z'");
    assert.equal(await scalar<number>("public.bsmart_push_prepare_slot()"), 0);
    assert.equal(await scalar("public.bsmart_push_claim()"), null);
    await db.exec("update public.test_clock set at='2026-10-01T14:01:00Z'");
    assert.equal(await scalar<number>("public.bsmart_push_prepare_slot()"), 1);
    const next = await scalar<any>("public.bsmart_push_claim()");
    assert.equal(next.item_count, 1);
    await db.query("update public.bsmart_push_devices set updated_at=public.test_now() where id=$1", [device]);
    assert.equal(await finish(next, 410, true), true);
    assert.equal(await scalar<boolean>("(select enabled from public.bsmart_push_devices where id=$1)", [device]), true,
      "Old receipt must not disable a newer registration");
    await event(user);
    await db.exec("update public.test_clock set at='2026-10-02T00:01:00Z'");
    assert.equal(await scalar<number>("public.bsmart_push_prepare_slot()"), 1);
    const invalid = await scalar<any>("public.bsmart_push_claim()");
    assert.equal(await finish(invalid, 410, true), true);
    assert.equal(await scalar<boolean>("(select enabled from public.bsmart_push_devices where id=$1)", [device]), false);
    await db.exec("update public.test_clock set at='2026-10-02T10:01:00Z'");
    await db.query("update public.bsmart_push_devices set enabled=true,updated_at=public.test_now() where id=$1", [device]);
    await event(user);
    assert.equal(await scalar<number>("public.bsmart_push_prepare_slot()"), 1);
    await db.query("update public.bsmart_push_devices set notify_authors=false,notify_tickers=false,notify_holdings=false where id=$1", [device]);
    assert.equal(await scalar("public.bsmart_push_claim()"), null, "Consent is checked again at claim");

    const identity = "TESTTEAM01:TESTKEY001:today.bsmart.ios";
    const jwt = "a".repeat(50) + "." + "b".repeat(50) + "." + "c".repeat(50);
    assert.equal(await scalar("public.bsmart_push_provider_token($1)", [identity]), null);
    const cached = await scalar<any>("public.bsmart_push_provider_token($1,$2)", [identity, jwt]);
    assert.equal(cached.token, jwt);
    assert.equal((await scalar<any>("public.bsmart_push_provider_token($1,$2)", [identity, jwt + "new"])).token, jwt,
      "First provider JWT wins across cold workers");
    await db.exec("update public.test_clock set at=at+interval '46 minutes'");
    assert.equal(await scalar("public.bsmart_push_provider_token($1)", [identity]), null);
    assert.equal((await scalar<any>("public.bsmart_push_provider_token($1,$2)", [identity, jwt + "new"])).token, jwt + "new");
    // Applying again does not replace the worker secret or duplicate its scheduled job.
    await db.exec((await Deno.readTextFile(new URL("202610010001_cloud_push_dispatch.sql", root)))
      .replaceAll("now()", "public.test_now()"));
    assert.equal(await scalar<number>("(select count(*)::integer from cron.job)"), 1);
    assert.equal(await scalar<boolean>("public.bsmart_push_worker_authorized($1)", ["ab".repeat(32)]), true);
    for (const role of ["anon", "authenticated"]) {
      await db.exec(`set role ${role}`);
      for (const sql of ["select * from public.bsmart_push_devices", "select * from public.bsmart_push_provider_tokens",
        "select public.bsmart_push_prepare_slot()", "select public.bsmart_push_claim()",
        "select public.bsmart_push_run_worker()", "select public.bsmart_push_worker_authorized('secret')",
        "select public.bsmart_push_provider_token('privateidentity')"]) {
        await assert.rejects(() => db.query(sql));
      }
      await db.exec("reset role");
    }
    await db.exec("set role service_role");
    assert.equal(await scalar<boolean>("public.bsmart_push_worker_authorized($1)", ["ab".repeat(32)]), true);
    await assert.rejects(() => db.query("select * from public.bsmart_push_provider_tokens"));
  } finally { await db.close(); }
});
