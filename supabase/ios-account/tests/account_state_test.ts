import { handleFeed } from "../supabase/functions/bsmart-feed/handler.ts";
import { followInput } from "../supabase/functions/bsmart-feed/account_state.ts";

function assert(value: unknown): asserts value { if (!value) throw new Error("assertion failed"); }

Deno.test("account preferences survive sessions and never cross authenticated users", async () => {
  const first = crypto.randomUUID(), second = crypto.randomUUID();
  let actor = first;
  const rows = new Map<string, any>();
  const client: any = {
    auth: { getUser: async () => ({ data: { user: { id: actor, identities: [{ provider: "google" }] } } }) },
    from: (table: string) => {
      assert(table === "bsmart_account_preferences");
      const filters: Record<string, unknown> = {};
      let patch: any;
      const query: any = {
        select: () => query,
        eq: (key: string, value: unknown) => { filters[key] = value; return query; },
        maybeSingle: async () => {
          const row = rows.get(String(filters.account_id));
          if (!row || (filters.revision !== undefined && row.revision !== filters.revision)) return { data: null };
          if (patch) { Object.assign(row, patch); return { data: { ...row } }; }
          return { data: { ...row } };
        },
        insert: async (value: any) => {
          if (rows.has(value.account_id)) return { error: { code: "23505" } };
          rows.set(value.account_id, { account_id: value.account_id, onboarding_completed: false,
            followed_authors: [], followed_money: [], revision: 0 });
          return { error: null };
        },
        update: (value: any) => { patch = value; return query; },
      };
      return query;
    },
  };
  const deps = { info: async () => ({}), catalog: async () => ({}) };
  const request = (path: string, method = "GET", value?: unknown) => new Request("https://test.invalid/bsmart-feed" + path, {
    method, headers: { Authorization: "Bearer a.b.c", "Content-Type": "application/json" },
    body: value === undefined ? undefined : JSON.stringify(value),
  });
  const state = await handleFeed(request("/state"), client, deps);
  assert(state.status === 200 && !(await state.json()).onboardingCompleted);
  const follow = await handleFeed(request("/state/follow", "PUT", { kind: "author", id: "x:one", following: true }), client, deps);
  assert(follow.status === 200 && (await follow.json()).followedAuthors[0] === "x:one");
  assert((await handleFeed(request("/state/onboarding", "PUT"), client, deps)).status === 200);
  const restored = await (await handleFeed(request("/state"), client, deps)).json();
  assert(restored.onboardingCompleted && restored.followedAuthors.length === 1);
  actor = second;
  const isolated = await (await handleFeed(request("/state"), client, deps)).json();
  assert(!isolated.onboardingCompleted && isolated.followedAuthors.length === 0);
  actor = first;
  const unfollow = await handleFeed(request("/state/follow", "PUT", { kind: "author", id: "x:one", following: false }), client, deps);
  assert(unfollow.status === 200 && (await unfollow.json()).followedAuthors.length === 0);
  assert((await handleFeed(request("/state/follow", "PUT", { kind: "money", id: "h:wallet", following: true }), client, deps)).status === 200);
  assert((await (await handleFeed(request("/state"), client, deps)).json()).followedMoney[0] === "h:wallet");
});

Deno.test("account preference writes reject extra fields and preserve private storage", async () => {
  for (const value of [{ kind: "author", id: "x:a", following: true, accountID: crypto.randomUUID() },
    { kind: "author", id: " x:a", following: true }, { kind: "invalid", id: "x:a", following: true },
    { kind: "money", id: "x:a", following: "yes" }]) {
    let failed = false;
    try { followInput(value); } catch { failed = true; }
    assert(failed);
  }
  const sql = await Deno.readTextFile(new URL("../supabase/migrations/202609230003_account_preferences.sql", import.meta.url));
  assert(sql.includes("enable row level security"));
  assert(sql.includes("revoke all on public.bsmart_account_preferences from anon, authenticated"));
  assert(sql.includes("references auth.users(id) on delete cascade"));
  assert(sql.includes("revision > 0 from public.bsmart_feed_profiles"));
});
