import { strict as assert } from "node:assert";
import { PGlite } from "npm:@electric-sql/pglite@0.5.8";
import { abilityLeaderboard } from "../supabase/functions/bsmart-feed/ability_leaderboard.ts";
import { handleFeed } from "../supabase/functions/bsmart-feed/handler.ts";

const actor = (
  actorKind: string,
  actorId: string,
  score: number | null,
  status = score === null ? "insufficient_history" : "scored",
) => ({
  actorKind,
  actorId,
  displayName: actorId,
  platform: actorKind === "platform" ? "X" : null,
  avatarURL: null,
  score,
  status,
  observedCalendarDays: 400,
  independentDecisionDays: 15,
  pricedCoverage: 0.95,
});

Deno.test("absolute Score leaderboard sorts every actor kind and leaves unscored actors unranked", () => {
  const items = [
    actor("institution", "fund", -8),
    actor("celebrity", "artist", null),
    actor("politician", "member", 178.5),
    actor("platform", "author", 178.5),
    actor("insider", "executive", 19),
  ];
  const result = abilityLeaderboard({
    scoring_version: "follow-ability-v1",
    revision: 1,
    as_of: "2026-09-29T00:00:00Z",
    items,
  });
  assert.equal(result.status, "published");
  assert.deepEqual(result.items.map((item) => [item.actorKind, item.rank]), [
    ["platform", 1],
    ["politician", 1],
    ["insider", 3],
    ["institution", 4],
    ["celebrity", null],
  ]);
  assert.equal(result.items[0].score, 178.5);
  assert.equal(result.items[3].score, -8);
  assert.deepEqual(abilityLeaderboard(null).items, []);
  for (
    const malformed of [
      { ...items[0], score: null, status: "scored" },
      { ...items[0], score: 10, status: "unaudited_backtest" },
      { ...items[0], score: Infinity },
    ]
  ) {
    assert.throws(() =>
      abilityLeaderboard({
        scoring_version: "follow-ability-v1",
        revision: 1,
        as_of: "2026-09-29T00:00:00Z",
        items: [malformed],
      })
    );
  }
  assert.throws(() =>
    abilityLeaderboard({
      scoring_version: "follow-ability-v1",
      revision: 1,
      as_of: "2026-09-29T00:00:00Z",
      items: [items[0], items[0]],
    })
  );
});

Deno.test("ability leaderboard route reads only the published snapshot and fails closed", async () => {
  let databaseError = false;
  const client: any = {
    auth: {
      getUser: async () => ({
        data: {
          user: {
            id: crypto.randomUUID(),
            identities: [{ provider: "apple" }],
          },
        },
      }),
    },
    from: (table: string) => {
      assert.equal(table, "bsmart_investor_ability_snapshot");
      const query: any = {
        select: () => query,
        eq: () => query,
        maybeSingle: async () => ({
          data: null,
          error: databaseError ? { message: "missing table" } : null,
        }),
      };
      return query;
    },
  };
  const deps: any = {
    info: async () => {
      throw Error("no exchange calls");
    },
    catalog: async () => ({}),
  };
  const url = "https://test.invalid/bsmart-feed/ability-leaderboard";
  assert.equal((await handleFeed(new Request(url), client, deps)).status, 401);
  const request = () =>
    new Request(url, { headers: { Authorization: "Bearer a.b.c" } });
  const response = await handleFeed(request(), client, deps);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal((await response.json()).status, "unpublished");
  databaseError = true;
  assert.equal((await handleFeed(request(), client, deps)).status, 503);
});

Deno.test("ability snapshot migration keeps client roles read-only and publishes one version", async () => {
  const db = new PGlite();
  try {
    await db.exec(
      "create role anon; create role authenticated; create role service_role bypassrls;",
    );
    const sql = await Deno.readTextFile(
      new URL(
        "../supabase/migrations/202609290002_investor_ability_leaderboard.sql",
        import.meta.url,
      ),
    );
    await db.exec(sql);
    const access = await db.query<
      { anonymous: boolean; authenticated: boolean; service: boolean }
    >(
      "select has_table_privilege('anon','public.bsmart_investor_ability_snapshot','select') as anonymous, " +
        "has_table_privilege('authenticated','public.bsmart_investor_ability_snapshot','select') as authenticated, " +
        "has_table_privilege('service_role','public.bsmart_investor_ability_snapshot','insert') as service",
    );
    assert.deepEqual(access.rows[0], {
      anonymous: false,
      authenticated: false,
      service: true,
    });
    await db.query(
      "insert into public.bsmart_investor_ability_snapshot(revision,scoring_version,as_of,items) values(1,'follow-ability-v1',now(),'[]')",
    );
    await assert.rejects(() =>
      db.query(
        "insert into public.bsmart_investor_ability_snapshot(revision,scoring_version,as_of,items) values(2,'follow-ability-v1',now(),'[]')",
      )
    );
  } finally {
    await db.close();
  }
});
