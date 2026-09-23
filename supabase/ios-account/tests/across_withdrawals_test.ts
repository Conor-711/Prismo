import { strict as assert } from "node:assert";
import { AcrossProviderError, handleAcross, reconcileAcross, usdcUnits, validQuote } from
  "../supabase/functions/bsmart-withdrawals/across_handler.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { mnemonicToAccount } from "npm:viem@2.56.3/accounts";

const wallet = "0x" + "1".repeat(40);
const recipient = "0x" + "2".repeat(40);
const request = (path: string, method = "GET", body?: unknown) => new Request(
  `https://test.supabase.co/functions/v1/bsmart-withdrawals${path}`,
  { method, headers: { authorization: "Bearer a.b.c", "content-type": "application/json" },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }) },
);

const quote = (amount: string) => ({
  depositId: "123456789", inputAmount: amount,
  inputToken: { chainId: 1337, address: "0x2100000000000000000000000000000000000000", decimals: 8 },
  outputToken: { chainId: 42161, address: "0xaf88d065e77c8cc2239327c5edb3a432268e5831", decimals: 6 },
  refundToken: { chainId: 999 }, expectedOutputAmount: "980000", minOutputAmount: "970000",
  fees: { submission: { amount: "10000", token: { decimals: 8, symbol: "USDC" } } },
  quoteExpiryTimestamp: Math.floor(Date.now() / 1000) + 90,
  swapTx: null,
  swapTxns: ["hypercore", "evm-gasless"].map((ecosystem, index) => ({
    stepId: `step-${index}`, ecosystem,
    typedData: { domain: { chainId: 999 }, types: { Transfer: [] }, primaryType: "Transfer", message: {} },
  })),
});

Deno.test("HyperCore decimal conversion and quote route validation fail closed", () => {
  assert.equal(usdcUnits("1.25"), "125000000");
  assert.equal(usdcUnits("0.000001"), "100");
  assert.equal(usdcUnits("0.0000001"), null);
  assert.equal(usdcUnits("0"), null);
  const valid = quote("125000000");
  assert.equal(validQuote(valid, "perps", "125000000"), true);
  assert.equal(validQuote({ ...valid, inputAmount: "1250000" }, "perps", "125000000"), false);
  assert.equal(validQuote({ ...valid, refundToken: { chainId: 42161 } }, "perps", "125000000"), false);
  assert.equal(validQuote({ ...valid, swapTx: {} }, "perps", "125000000"), false);
  assert.equal(validQuote({ ...valid, swapTx: undefined }, "perps", "125000000"), false);
  assert.equal(validQuote({ ...valid, fees: { submission: null } }, "perps", "125000000"), false);
  assert.equal(validQuote({ ...valid, quoteExpiryTimestamp: 1 }, "perps", "125000000"), false);
  assert.equal(validQuote(valid, "spot", "125000000"), false);
});

Deno.test("legacy submissions are refused and disabled Across cannot request quotes", async () => {
  let calls = 0;
  const client = {
    auth: { getUser: async () => ({ data: { user: { id: crypto.randomUUID(), identities: [{ provider: "apple" }] } }, error: null }) },
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => {
      calls++; return { data: { address: wallet }, error: null };
    } }) }) }),
  } as unknown as SupabaseClient;
  assert.equal((await handleAcross(request("", "POST", {}), client, false, undefined, undefined)).status, 426);
  assert.equal(calls, 0);
  const input = { id: crypto.randomUUID(), walletAddress: wallet, recipient, amount: "1", sourceDex: "perps" };
  assert.equal((await handleAcross(request("/quote", "POST", input), client, false, undefined, undefined)).status, 503);
  assert.equal(calls, 1);
});

Deno.test("Across quote failures distinguish unsupported amounts from service errors", async () => {
  const client = {
    auth: { getUser: async () => ({ data: { user: { id: crypto.randomUUID(),
      is_anonymous: false, identities: [{ provider: "apple" }] } }, error: null }) },
    from: (name: string) => {
      const query = {
        select: () => query,
        eq: () => query,
        in: () => query,
        maybeSingle: async () => ({ data: { address: wallet }, error: null }),
        limit: async () => ({ data: [], error: null }),
      };
      assert.ok(["bsmart_wallets", "bsmart_withdrawals"].includes(name));
      return query;
    },
  } as unknown as SupabaseClient;
  const input = { id: crypto.randomUUID(), walletAddress: wallet, recipient, amount: "1", sourceDex: "perps" };
  const ports = (error: Error) => ({ quote: async () => { throw error; },
    submit: async () => ({}), status: async () => ({}) });
  const unavailableAmount = await handleAcross(request("/quote", "POST", input), client, true, "key", "0xdead",
    ports(new AcrossProviderError(400, "AMOUNT_TOO_LOW")));
  assert.equal(unavailableAmount.status, 422);
  assert.equal((await unavailableAmount.json()).error, "quote_unavailable");
  const unauthorized = await handleAcross(request("/quote", "POST", input), client, true, "key", "0xdead",
    ports(new AcrossProviderError(403, "FORBIDDEN_API_KEY")));
  assert.equal(unauthorized.status, 503);
  assert.equal((await unauthorized.json()).error, "provider_not_authorized");
  const providerDown = await handleAcross(request("/quote", "POST", input), client, true, "key", "0xdead",
    ports(new Error("network")));
  assert.equal(providerDown.status, 503);
  assert.equal((await providerDown.json()).error, "provider_unavailable");
});

Deno.test("background reconciliation requires the Vault token before reading records", async () => {
  let read = false;
  const client = {
    rpc: async () => ({ data: false, error: null }),
    from: () => { read = true; throw new Error("unreachable"); },
  } as unknown as SupabaseClient;
  const ports = { quote: async () => ({}), submit: async () => ({}), status: async () => ({}) };
  const req = new Request("https://test.supabase.co/functions/v1/bsmart-withdrawals/reconcile", {
    method: "POST", headers: { authorization: `Bearer ${"a".repeat(64)}` },
  });
  assert.equal((await reconcileAcross(req, client, ports)).status, 401);
  assert.equal(read, false);
});

Deno.test("a verified two-step withdrawal can submit once, never replay", async () => {
  const signer = mnemonicToAccount(Array(23).fill("abandon").concat("art").join(" "));
  const owner = signer.address.toLowerCase();
  const accountID = crypto.randomUUID();
  const id = crypto.randomUUID();
  const typed = {
    domain: { name: "bSmart test", version: "1", chainId: 999 },
    types: { Authorize: [{ name: "owner", type: "address" }, { name: "amount", type: "uint256" }] },
    primaryType: "Authorize" as const,
    message: { owner: signer.address, amount: 100000000n },
  };
  const providerQuote = {
    ...quote("100000000"),
    swapTxns: ["hypercore", "evm-gasless"].map((ecosystem, index) => ({
      stepId: `step-${index}`, ecosystem,
      typedData: { ...typed, message: { owner: signer.address, amount: "100000000" } },
    })),
  };
  let stored: Record<string, unknown> | null = null, submits = 0;
  const client = {
    auth: { getUser: async () => ({ data: { user: { id: accountID,
      is_anonymous: false, identities: [{ provider: "apple" }] } }, error: null }) },
    from: (name: string) => {
      const filters: Record<string, unknown> = {};
      let changes: Record<string, unknown> | null = null;
      const query = {
        select: () => query,
        eq: (field: string, value: unknown) => { filters[field] = value; return query; },
        in: () => query,
        limit: async () => ({ data: [], error: null }),
        update: (value: Record<string, unknown>) => { changes = value; return query; },
        maybeSingle: async () => {
          if (name === "bsmart_wallets") return { data: { address: owner }, error: null };
          if (!stored || filters.id !== id) return { data: null, error: null };
          if (changes) {
            if (stored.state !== filters.state) return { data: null, error: null };
            stored = { ...stored, ...changes };
          }
          return { data: stored, error: null };
        },
      };
      return query;
    },
    rpc: async (_name: string, args: Record<string, unknown>) => {
      stored = { id, account_id: accountID, wallet_address: owner,
        recipient, source_dex: "perps", amount_units: args.p_amount_units,
        quote: providerQuote, quote_expires_at: args.p_quote_expires_at,
        deposit_id: providerQuote.depositId, state: "quoted", provider_status: null,
        checked_at: null, created_at: new Date().toISOString() };
      return { data: stored, error: null };
    },
  } as unknown as SupabaseClient;
  const ports = {
    quote: async () => providerQuote,
    submit: async () => { submits++; return { depositId: providerQuote.depositId }; },
    status: async () => ({ status: "deposit-pending" }),
  };
  const payload = { id, walletAddress: owner, recipient, amount: "1", sourceDex: "perps" };
  const quoted = await handleAcross(request("/quote", "POST", payload), client, true, "key", "0xdead", ports);
  assert.equal(quoted.status, 201);
  const signature = await signer.signTypedData(typed);
  const body = { signaturesByStepId: { "step-0": signature, "step-1": signature } };
  const first = await handleAcross(request(`/${id}/submit`, "POST", body), client, true, "key", "0xdead", ports);
  assert.equal(first.status, 200);
  assert.equal((await first.json()).withdrawal.state, "submitted");
  assert.equal((await handleAcross(request(`/${id}/submit`, "POST", body), client, true, "key", "0xdead", ports)).status, 409);
  assert.equal(submits, 1);
});
