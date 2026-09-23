import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { type Challenge, validAddress, verifyBinding } from "./proof.ts";

const reply = (body: unknown, status = 200) => Response.json(body, {
  status, headers: { "Cache-Control": "no-store" },
});
const hex = (bytes: Uint8Array) => Array.from(bytes, b => b.toString(16).padStart(2, "0")).join("");

async function input(req: Request, keys: string[]): Promise<Record<string, string>> {
  if (!req.headers.get("content-type")?.startsWith("application/json")) throw new Error("invalid_input");
  const reader = req.body?.getReader();
  if (!reader) throw new Error("invalid_input");
  let size = 0, text = "";
  const decoder = new TextDecoder("utf-8", { fatal: true });
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 4096) throw new Error("invalid_input");
      text += decoder.decode(value, { stream: true });
    }
    text += decoder.decode();
  } finally { await reader.cancel(); }
  const data = JSON.parse(text);
  if (!data || typeof data !== "object" || Array.isArray(data) || Object.keys(data).length !== keys.length ||
      !keys.every(k => typeof data[k] === "string")) throw new Error("invalid_input");
  return data;
}

function databaseError(error: { code?: string; message?: string }): Response {
  if (error.code === "23505") return reply({ error: "wallet_conflict" }, 409);
  if (error.code === "22023") return reply({ error: "invalid_proof" }, 422);
  if (error.message === "rate_limit") return reply({ error: "rate_limit" }, 429);
  return reply({ error: "wallet_setup_unavailable" }, 503);
}

export type TradingCapabilities = { depositsEnabled: boolean; tradingEnabled: boolean; withdrawalsEnabled: false;
  acrossWithdrawalsEnabled?: boolean };
export const closedCapabilities: TradingCapabilities = {
  depositsEnabled: false, tradingEnabled: false, withdrawalsEnabled: false, acrossWithdrawalsEnabled: false,
};

export async function handle(req: Request, client: SupabaseClient,
                             capabilities: TradingCapabilities = closedCapabilities): Promise<Response> {
  const path = new URL(req.url).pathname.replace(/\/$/, "");
  const root = path.endsWith("/bsmart-wallet");
  const challenge = path.endsWith("/bsmart-wallet/challenges");
  if (!(root && ["GET", "PUT"].includes(req.method)) && !(challenge && req.method === "POST")) {
    return reply({ error: "not_found" }, 404);
  }
  const authorization = req.headers.get("authorization") ?? "";
  if (!/^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(authorization) ||
      authorization.length > 16400) return reply({ error: "unauthorized" }, 401);
  const token = authorization.slice(7);
  try {
    // getUser performs server-side verification. Never use unverified JWT decoding or getSession here.
    const { data: { user }, error: authError } = await client.auth.getUser(token);
    if (authError || !user || user.is_anonymous || !user.identities?.some(i => ["apple", "google"].includes(i.provider))) {
      return reply({ error: "unauthorized" }, 401);
    }
    const account = user.id;
    if (req.method === "GET") {
      const { data, error } = await client.from("bsmart_wallets").select("address").eq("account_id", account).maybeSingle();
      if (error) return databaseError(error);
      return reply({ accountId: account, address: data?.address ?? null,
        capabilities: data?.address ? capabilities : closedCapabilities });
    }
    const tokenHash = hex(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token))));
    if (challenge) {
      const body = await input(req, ["address"]);
      if (!validAddress(body.address)) return reply({ error: "invalid_address" }, 422);
      const { data, error } = await client.rpc("bsmart_wallet_challenge", {
        p_account: account, p_token_hash: tokenHash, p_address: body.address,
        p_nonce: hex(crypto.getRandomValues(new Uint8Array(32))),
      });
      return error ? databaseError(error) : reply(data);
    }
    const body = await input(req, ["challengeId", "signature"]);
    if (!/^[0-9a-f-]{36}$/.test(body.challengeId) || !/^0x[0-9a-fA-F]{130}$/.test(body.signature)) {
      return reply({ error: "invalid_proof" }, 422);
    }
    const params = { p_account: account, p_token_hash: tokenHash, p_id: body.challengeId };
    const { data: proof, error } = await client.rpc("bsmart_wallet_challenge_read", params);
    if (error) return databaseError(error);
    if (!await verifyBinding(proof as Challenge, account, body.signature)) return reply({ error: "invalid_proof" }, 422);
    const result = await client.rpc("bsmart_wallet_commit", params);
    return result.error ? databaseError(result.error) : reply({ ...result.data, capabilities });
  } catch {
    // Never return/log credentials, wallet signatures, SQL diagnostics or request bodies.
    return reply({ error: "request_failed" }, 400);
  }
}
