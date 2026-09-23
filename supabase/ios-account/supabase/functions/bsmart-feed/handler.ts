import type { SupabaseClient, User } from "npm:@supabase/supabase-js@2.116.0";
import { type InfoReader, type Intent, uuid, validateIntent, verifyHip3Market } from "./verification.ts";
import { reconcile } from "./reconcile.ts";
import { resolveAvatars } from "../bsmart-profile/avatars.ts";
import { subjectScope, validCatalogSource } from "./subject.ts";
import { mutateThesis } from "./theses.ts";
import { rankingScope } from "./rankings.ts";
import { publicPortfolio } from "./public_portfolio.ts";
import { finishAccountOnboarding, followInput, readAccountState, setAccountFollow } from "./account_state.ts";

export type Dependencies = {
  info: InfoReader;
  catalog: (opinionId: string, authorId: string) => Promise<any>;
  now?: () => number;
};
const reply = (body: unknown, status = 200) => Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
const failure = () => reply({ error: "feed_unavailable" }, 503);

async function body(req: Request): Promise<any> {
  if (!req.headers.get("content-type")?.startsWith("application/json")) throw new Error("invalid_input");
  const reader = req.body?.getReader(); if (!reader) throw new Error("invalid_input");
  let size = 0, text = ""; const decoder = new TextDecoder("utf-8", { fatal: true });
  try {
    while (true) {
      const { done, value } = await reader.read(); if (done) break;
      size += value.length; if (size > 16384) throw new Error("invalid_input");
      text += decoder.decode(value, { stream: true });
    }
    text += decoder.decode();
  } finally { await reader.cancel(); }
  return JSON.parse(text);
}
const profile = (p: any) => ({ id: p.public_id, nickname: p.nickname, handle: p.handle,
  avatarURL: p.avatar_url, bio: p.bio });

export function sharingInput(input: any, _user?: User) {
  // Compatibility only: activity is public; old clients cannot hide it or overwrite identity.
  if (!input || !["feedVisible,visible", "feedVisible,nickname,useProviderAvatar,visible"].includes(Object.keys(input).sort().join()) ||
      ![input.visible, input.feedVisible].every(v => typeof v === "boolean")) throw new Error("invalid_input");
  return { visible: true, feed_visible: true };
}

async function register(req: Request, client: SupabaseClient, user: User, deps: Dependencies, now: number) {
  const i = validateIntent(await body(req), now);
  const [walletResult, oldResult] = await Promise.all([
    client.from("bsmart_wallets").select("address").eq("account_id", user.id).maybeSingle(),
    client.from("bsmart_feed_orders").select("id,account_id,intent").eq("cloid", i.cloid).maybeSingle(),
  ]);
  const { data: wallet, error: walletError } = walletResult;
  if (walletError) return failure();
  if (!wallet?.address) return reply({ error: "wallet_required" }, 409);
  const { data: old, error: oldError } = oldResult;
  if (oldError) return failure();
  if (old) {
    if (old.account_id !== user.id || !Object.keys(i).every(k => i[k as keyof Intent] === old.intent[k])) {
      return reply({ error: "attribution_conflict" }, 409);
    }
    return reply({ id: old.id, cloid: i.cloid });
  }
  const { count, error: countError } = await client.from("bsmart_feed_orders").select("id", { count: "exact", head: true })
    .eq("account_id", user.id).gte("registered_at", new Date(now - 60000).toISOString());
  if (countError) return failure();
  if ((count ?? 0) >= 20) return reply({ error: "rate_limit" }, 429);
  const [opinion, status] = await Promise.all([
    deps.catalog(i.opinionId, i.authorId),
    deps.info({ type: "orderStatus", user: wallet.address, oid: i.cloid }),
  ]);
  if (!validCatalogSource(opinion, i, now)) {
    return reply({ error: "opinion_unavailable" }, 422);
  }
  // No retrospective attribution, including an order already visible on the exchange.
  if (status?.status !== "unknownOid") return reply({ error: "existing_order" }, 409);
  await verifyHip3Market(i, deps.info);
  validateIntent(i, deps.now?.() ?? Date.now());
  const { data, error } = await client.from("bsmart_feed_orders").insert({
    account_id: user.id, wallet: wallet.address, cloid: i.cloid, opinion_id: i.opinionId, intent: i, opinion,
  }).select("id").single();
  return error ? failure() : reply({ id: data.id, cloid: i.cloid });
}

async function sync(req: Request, client: SupabaseClient, user: User, deps: Dependencies, now: number) {
  const input = await body(req);
  if (!input || typeof input !== "object" || Array.isArray(input) ||
      Object.keys(input).some(k => k !== "cloid") ||
      (input.cloid !== undefined && (typeof input.cloid !== "string" || !/^0x[0-9a-f]{32}$/.test(input.cloid)))) {
    return reply({ error: "invalid_input" }, 422);
  }
  return reply(await reconcile(client, deps.info, user.id, input.cloid ?? null, 1, now));
}

export async function handleFeed(req: Request, client: SupabaseClient, deps: Dependencies): Promise<Response> {
  const url = new URL(req.url), path = url.pathname.split("/bsmart-feed")[1]?.replace(/\/$/, "") ?? "!";
  const authorization = req.headers.get("authorization") ?? "";
  if (!/^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(authorization) || authorization.length > 16400) {
    return reply({ error: "unauthorized" }, 401);
  }
  try {
    const { data: { user }, error: authError } = await client.auth.getUser(authorization.slice(7));
    if (authError || !user || user.is_anonymous || !user.identities?.some(i => ["google", "apple"].includes(i.provider))) {
      return reply({ error: "unauthorized" }, 401);
    }
    const now = deps.now?.() ?? Date.now();
    if (path === "/state" && req.method === "GET") return reply(await readAccountState(client, user.id));
    if (path === "/state/follow" && req.method === "PUT") {
      return reply(await setAccountFollow(client, user.id, followInput(await body(req))));
    }
    if (path === "/state/onboarding" && req.method === "PUT") {
      return reply(await finishAccountOnboarding(client, user.id));
    }
    if (path === "/orders" && req.method === "POST") return await register(req, client, user, deps, now);
    if (path === "/sync" && req.method === "POST") return await sync(req, client, user, deps, now);
    if (path === "/sharing" && ["GET", "PUT"].includes(req.method)) {
      const { error: ensureError } = await client.rpc("bsmart_profile_ensure", { p_account: user.id });
      if (ensureError) return failure();
      if (req.method === "PUT") {
        const settings = sharingInput(await body(req), user);
        const { error } = await client.from("bsmart_feed_profiles").update({ ...settings,
          updated_at: new Date(now).toISOString() }).eq("account_id", user.id);
        if (error) return failure();
      }
      const { data, error } = await client.from("bsmart_feed_profiles").select("*").eq("account_id", user.id).maybeSingle();
      return error || !data ? failure() : reply(await resolveAvatars(client, { nickname: data.nickname, handle: data.handle, avatarURL: data.avatar_url,
        visible: true, feedVisible: true,
        useProviderAvatar: !!data?.avatar_url?.startsWith("https:") }));
    }
    if (req.method === "PUT" && /^\/(trades|theses)\//.test(path)) {
      const result = await mutateThesis(path, await body(req), client, user.id);
      return reply(result.body, result.status);
    }
    const activity = path.match(/^\/orders\/(0x[0-9a-f]{32})\/activity$/);
    if (req.method === "GET" && activity) {
      const { data, error } = await client.rpc("bsmart_feed_social_page", {
        p_actor: user.id, p_offset: 0, p_limit: 1, p_cloid: activity[1],
      });
      if (error?.code === "PGRST202") return reply({ error: "thesis_not_ready" }, 503);
      if (error || !data) return failure();
      return data.items?.[0] ? reply(await resolveAvatars(client, data.items[0])) : reply({ error: "trade_pending" }, 409);
    }
    if (req.method !== "GET") return reply({ error: "not_found" }, 404);
    if (path === "/subject-stats") {
      const { data, error } = await client.rpc("bsmart_subject_trade_stats", subjectScope(url));
      return error || !data ? failure() : reply(data);
    }
    const offset = Number(url.searchParams.get("offset") ?? "0"), limit = Number(url.searchParams.get("limit") ?? "10");
    if (!Number.isSafeInteger(offset) || offset < 0 || offset > 10000 || !Number.isInteger(limit) || limit < 1 || limit > 30) {
      return reply({ error: "invalid_page" }, 422);
    }
    const profileMatch = path.match(/^\/profiles\/([^/]+)$/);
    const portfolioMatch = path.match(/^\/profiles\/([^/]+)\/portfolio$/);
    if (portfolioMatch && uuid(portfolioMatch[1])) {
      const value = await publicPortfolio(client, deps.info, portfolioMatch[1]);
      return value ? reply(value) : reply({ error: "not_found" }, 404);
    }
    if (path === "/rankings") {
      const { data, error } = await client.rpc("bsmart_discovery_rankings", {
        ...rankingScope(url, now), p_offset: offset, p_limit: limit,
      });
      return error || !data ? failure() : reply(await resolveAvatars(client, data));
    }
    if (path === "/popular") {
      const { data, error } = await client.rpc("bsmart_feed_popular", { p_offset: offset, p_limit: limit });
      return error ? failure() : reply(data);
    }
    if (profileMatch && uuid(profileMatch[1])) {
      const { data, error } = await client.from("bsmart_feed_profiles").select("public_id,nickname,handle,avatar_url,bio")
        .eq("public_id", profileMatch[1]).eq("visible", true).eq("feed_visible", true).maybeSingle();
      return error ? failure() : data ? reply(await resolveAvatars(client, profile(data))) : reply({ error: "not_found" }, 404);
    }
    if (path === "") {
      const id = url.searchParams.get("profileId");
      if (id !== null && !uuid(id)) return reply({ error: "invalid_profile" }, 422);
      const includeTheses = url.searchParams.get("includeTheses");
      if (includeTheses !== null && !["true", "false"].includes(includeTheses)) return reply({ error: "invalid_input" }, 422);
      const mine = url.searchParams.get("mine");
      if ((mine !== null && !["true", "false"].includes(mine)) || (mine === "true" && id !== null)) {
        return reply({ error: "invalid_input" }, 422);
      }
      if (includeTheses !== "true") {
        if (mine === "true") return reply({ error: "invalid_input" }, 422);
        const { data, error } = await client.rpc("bsmart_feed_page", { p_offset: offset, p_limit: limit, p_profile: id });
        return error ? failure() : reply(await resolveAvatars(client, data));
      }
      const { data, error } = await client.rpc("bsmart_feed_social_page", {
        p_actor: user.id, p_offset: offset, p_limit: limit, p_profile: id, p_mine: mine === "true",
      });
      // Public feeds remain readable during the thesis migration rollout. Never
      // substitute the public feed for the owner's private activity or hide other errors.
      if (error?.code === "PGRST202" && mine !== "true") {
        const legacy = await client.rpc("bsmart_feed_page", { p_offset: offset, p_limit: limit, p_profile: id });
        return legacy.error ? failure() : reply(await resolveAvatars(client, legacy.data));
      }
      return error ? failure() : reply(await resolveAvatars(client, data));
    }
    const opinionMatch = path.match(/^\/opinions\/([^/]+)\/traders$/);
    if (opinionMatch && uuid(opinionMatch[1])) {
      const { data, error } = await client.rpc("bsmart_opinion_traders", {
        p_opinion: opinionMatch[1], p_offset: offset, p_limit: limit,
      });
      return error ? failure() : reply(await resolveAvatars(client, data));
    }
    return reply({ error: "not_found" }, 404);
  } catch (error) {
    if (error instanceof Error && error.message === "opinion_unavailable") return reply({ error: "opinion_unavailable" }, 422);
    if (error instanceof Error && error.message === "market_unavailable") return reply({ error: "market_unavailable" }, 422);
    if (error instanceof Error && error.message === "state_conflict") return reply({ error: "state_conflict" }, 409);
    if (error instanceof Error && error.message === "follow_limit") return reply({ error: "follow_limit" }, 422);
    const invalid = error instanceof Error && ["invalid_input", "invalid_intent", "invalid_decimal"].includes(error.message);
    return invalid ? reply({ error: "invalid_input" }, 422) : failure();
  }
}
