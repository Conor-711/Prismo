import { strict as assert } from "node:assert";
import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { mnemonicToAccount } from "npm:viem@2.56.3/accounts";
import { type Challenge, bindingMessage, verifyBinding } from "../supabase/functions/bsmart-wallet/proof.ts";
import { closedCapabilities, handle } from "../supabase/functions/bsmart-wallet/handler.ts";

// Public BIP39 zero-entropy vector, also verified by DeviceWalletCryptographyTests.swift.
const wallet = mnemonicToAccount(Array(23).fill("abandon").concat("art").join(" "));
const account = "00000000-0000-0000-0000-000000000001";
const base: Challenge = {
  id: "00000000-0000-0000-0000-000000000002", accountId: account,
  address: wallet.address.toLowerCase(), nonce: "a".repeat(64),
  issuedAt: "2026-09-10T00:00:00Z", expiresAt: "2026-09-10T00:05:00Z",
};
const vector = "0x219475024e82689a618eb2bfd96d6c1cbc4118665f16130d6530301be46be8261bc248cb708cd88fd86082a27f94d12af0aa3e48e249b53d4a322b02f11e31301b";
const now = Date.parse(base.issuedAt);
const token = "disposable.header.signature";

Deno.test("EIP-191 proof matches the native Swift and Python vector", async () => {
  assert.equal(base.address, "0xf278cf59f82edcf871d630f28ecc8056f25c1cdb");
  assert.equal(await wallet.signMessage({ message: bindingMessage(base, account, now) }), vector);
  assert.equal(await verifyBinding(base, account, vector, now), true);
});

Deno.test("wrong account, address, nonce, expiry and future timestamp cannot verify", async () => {
  assert.equal(await verifyBinding(base, crypto.randomUUID(), vector, now), false);
  for (const patch of [
    { address: "0x" + "1".repeat(40) }, { nonce: "b".repeat(64) }, { id: crypto.randomUUID() },
    { expiresAt: base.issuedAt }, { issuedAt: "2026-09-10T01:00:00Z" },
  ]) assert.equal(await verifyBinding({ ...base, ...patch }, account, vector, now), false);
  assert.equal(await verifyBinding(base, account, vector, now + 300001), false);
  assert.equal(await verifyBinding(base, account, "0x123", now), false);
});

function fixture(options: { missing?: boolean; anonymous?: boolean; authFailure?: boolean; bound?: boolean } = {}) {
  const calls: string[] = [];
  const pending = { ...base, issuedAt: new Date(Math.floor(Date.now() / 1000) * 1000).toISOString().replace(".000", ""),
    expiresAt: new Date(Math.floor(Date.now() / 1000) * 1000 + 300000).toISOString().replace(".000", "") };
  let consumed = false;
  const client = createClient("https://test.supabase.co", "disposable-test-service-key", {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { fetch: async (input, init) => {
      const url = new URL(String(input)); calls.push(url.pathname);
      if (url.pathname === "/auth/v1/user") {
        if (options.authFailure) return Response.json({ message: "rejected" }, { status: 401 });
        return Response.json({ id: account, is_anonymous: options.anonymous ?? false,
          identities: [{ provider: "google", identity_data: { sub: "verified-google-subject" } }] });
      }
      if (options.missing) return Response.json({ code: "42P01", message: "missing table" }, { status: 404 });
      if (url.pathname === "/rest/v1/bsmart_wallets") return Response.json(options.bound ? [{ address: base.address }] : []);
      const body = JSON.parse(String(init?.body));
      assert.equal(body.p_account, account);
      assert.match(body.p_token_hash, /^[a-f0-9]{64}$/);
      assert.notEqual(body.p_token_hash, token);
      if (url.pathname.endsWith("bsmart_wallet_challenge")) return Response.json(pending);
      if (consumed) return Response.json({ code: "22023" }, { status: 400 });
      if (url.pathname.endsWith("bsmart_wallet_challenge_read")) return Response.json(pending);
      if (url.pathname.endsWith("bsmart_wallet_commit")) {
        consumed = true; return Response.json({ accountId: account, address: pending.address });
      }
      throw new Error("Unexpected test request");
    } },
  });
  return { client, calls, pending };
}

function request(method = "GET", body?: unknown, path = "", bearer = token) {
  return new Request("https://test.supabase.co/functions/v1/bsmart-wallet" + path, {
    method, headers: { "Authorization": "Bearer " + bearer, "Content-Type": "application/json" },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}

Deno.test("unauthenticated and anonymous callers never read or write registry", async () => {
  for (const options of [{ anonymous: true }, { authFailure: true }]) {
    const f = fixture(options);
    assert.equal((await handle(request(), f.client)).status, 401);
    assert.deepEqual(f.calls, ["/auth/v1/user"]);
  }
  const f = fixture();
  assert.equal((await handle(request("GET", undefined, "", "invalid"), f.client)).status, 401);
  assert.equal(f.calls.length, 0);
});

Deno.test("registry missing is an error, only a successful empty read returns null", async () => {
  assert.equal((await handle(request(), fixture({ missing: true }).client)).status, 503);
  const result = await handle(request(), fixture().client);
  assert.deepEqual(await result.json(), { accountId: account, address: null, capabilities: closedCapabilities });
  assert.equal(result.headers.get("cache-control"), "no-store");
});

Deno.test("capabilities default closed and require a bound wallet", async () => {
  const open = { depositsEnabled: true, tradingEnabled: true, withdrawalsEnabled: true };
  for (const bound of [false, true]) {
    const result = await handle(request(), fixture({ bound }).client, open);
    assert.deepEqual((await result.json()).capabilities, bound ? open : closedCapabilities);
  }
  const result = await handle(request(), fixture({ bound: true }).client);
  assert.deepEqual((await result.json()).capabilities, closedCapabilities);
});

Deno.test("capability switches are independent and proof success receives them", async () => {
  const flags = { depositsEnabled: true, tradingEnabled: false, withdrawalsEnabled: true };
  const f = fixture();
  const signature = await wallet.signMessage({ message: bindingMessage(f.pending, account) });
  const response = await handle(request("PUT", { challengeId: f.pending.id, signature }), f.client, flags);
  assert.equal(response.status, 200);
  assert.deepEqual((await response.json()).capabilities, flags);
  const read = await handle(request(), fixture({ bound: true }).client, flags);
  assert.deepEqual((await read.json()).capabilities, flags);
});

Deno.test("a valid wallet proof commits once, replay cannot commit again", async () => {
  const f = fixture();
  const signature = await wallet.signMessage({ message: bindingMessage(f.pending, account) });
  const body = { challengeId: f.pending.id, signature };
  assert.equal((await handle(request("PUT", body), f.client)).status, 200);
  assert.equal((await handle(request("PUT", body), f.client)).status, 422);
  assert.equal(f.calls.filter(c => c.endsWith("bsmart_wallet_commit")).length, 1);
});

Deno.test("invalid proof never reaches the commit RPC", async () => {
  const f = fixture();
  assert.equal((await handle(request("PUT", { challengeId: f.pending.id, signature: vector }), f.client)).status, 422);
  assert.equal(f.calls.some(c => c.endsWith("bsmart_wallet_commit")), false);
});

Deno.test("client-supplied account IDs and oversized bodies are rejected", async () => {
  const f = fixture();
  assert.equal((await handle(request("POST", { address: base.address, accountId: crypto.randomUUID() }, "/challenges"), f.client)).status, 400);
  assert.equal((await handle(request("POST", { address: "x".repeat(5000) }, "/challenges"), f.client)).status, 400);
  assert.equal(f.calls.some(c => c.includes("/rpc/")), false);
});

Deno.test("challenge creation derives identity from auth, not request input", async () => {
  const f = fixture();
  const response = await handle(request("POST", { address: base.address }, "/challenges"), f.client);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).accountId, account);
});
