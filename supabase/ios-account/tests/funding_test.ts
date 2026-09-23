import { strict as assert } from "node:assert";
import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { PGlite } from "npm:@electric-sql/pglite@0.5.8";
import { amountMicro, amountUnits, parseQuote, parseDeposits, quoteBody, PERPS, networks, RelayFunding } from "../supabase/functions/bsmart-funding/relay.ts";
import { handle } from "../supabase/functions/bsmart-funding/handler.ts";

const owner = "0x" + "1".repeat(40), deposit = "0x" + "2".repeat(40);
const account = "00000000-0000-0000-0000-000000000001";
const config = { enabled: true, relayKey: "disposable-key" };
function quote(network: keyof typeof networks = "arbitrum", amount = "100000000") {
  return { steps: [{ id: "deposit", kind: "transaction", depositAddress: deposit, requestId: "0x" + "a".repeat(64) }],
    details: { sender: owner, recipient: owner,
      currencyIn: { currency: { chainId: networks[network].chainId, address: networks[network].token,
        decimals: networks[network].decimals }, amount },
      currencyOut: { currency: { chainId: 1337, address: PERPS, decimals: 8 },
        amount: "9900000000", minimumAmount: "9850500000", amountFormatted: "99.0" } } };
}
function request(path = "", method = "GET", body?: unknown, token = "a.b.c") {
  return new Request("https://test.supabase.co/functions/v1/bsmart-funding" + path, {
    method, headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
}
type AddressStore = { rows: Map<string, Record<string, unknown>>; readError?: boolean; writeError?: boolean };
function fixture(anonymous = false, store: AddressStore = { rows: new Map() }) {
  const client = createClient("https://test.supabase.co", "disposable", {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { fetch: async (input, init) => {
      const url = new URL(String(input));
      if (url.pathname === "/auth/v1/user") return Response.json({ id: account, is_anonymous: anonymous,
        identities: [{ provider: "apple" }] });
      if (url.pathname === "/rest/v1/bsmart_funding_addresses") {
        if (init?.method === "POST") {
          if (store.writeError) return Response.json({ message: "unavailable" }, { status: 503 });
          assert.match(new Headers(init.headers).get("Prefer") ?? "", /resolution=ignore-duplicates/);
          const row = JSON.parse(String(init.body)) as Record<string, unknown>;
          const key = [row.account_id, row.wallet_address, row.network].join(":");
          if (!store.rows.has(key)) store.rows.set(key, { ...row, created_at: "2026-09-23T00:00:00Z" });
          return new Response(null, { status: 201 });
        }
        if (store.readError) return Response.json({ message: "unavailable" }, { status: 503 });
        const key = [account, owner, url.searchParams.get("network")?.slice(3)].join(":");
        const row = store.rows.get(key);
        return Response.json(row ? [row] : []);
      }
      assert.equal(url.pathname, "/rest/v1/bsmart_wallets");
      assert.equal(url.searchParams.get("account_id"), "eq." + account);
      return Response.json([{ address: owner }]);
    } },
  });
  return client;
}

Deno.test("amounts use integer USDC units and reject zero, exponents and excess precision", () => {
  assert.equal(amountMicro("0.000001"), "1");
  assert.equal(amountMicro("100.123456"), "100123456");
  for (const input of ["0", "-1", "1e6", "01", "1.0000001", "Infinity", 100, "10000000", " 1"]) {
    assert.throws(() => amountMicro(input));
  }
});
Deno.test("provider destination is perps, refund belongs to owner, no wallet transaction is submitted", async () => {
  const body = quoteBody(owner, "arbitrum", "100");
  assert.equal(body.destinationChainId, 1337);
  assert.equal(body.destinationCurrency, PERPS);
  assert.equal(body.recipient, owner); assert.equal(body.refundTo, owner);
  assert.equal(body.useDepositAddress, true);
  assert.equal(body.strict, false);
  assert.equal(body.slippageTolerance, "50");
  const client = new RelayFunding("secret-test-key", async (url, init) => {
    assert.equal(url, "https://api.relay.link/quote/v2");
    assert.equal(init?.redirect, "error");
    assert.equal(new Headers(init?.headers).get("x-api-key"), "secret-test-key");
    assert.deepEqual(JSON.parse(String(init?.body)), body);
    return Response.json(quote());
  });
  assert.equal((await client.quote(owner, "arbitrum", "100")).depositAddress, deposit);
});
Deno.test("Monad native USDC has a separate validated deposit route", async () => {
  const body = quoteBody(owner, "monad", "20");
  assert.equal(body.originChainId, 143);
  assert.equal(body.originCurrency, "0x754704bc059f8c67012fed69bc8a327a5aafb603");
  assert.equal(body.destinationChainId, 1337);
  assert.equal(body.destinationCurrency, PERPS);
  assert.equal(body.refundTo, owner);
  const monadQuote = quote("monad", "20000000");
  assert.equal(parseQuote(monadQuote, owner, "monad", "20").depositAddress, deposit);
  assert.throws(() => parseQuote(monadQuote, owner, "base", "20"));
  assert.throws(() => parseQuote(monadQuote, owner, "arbitrum", "20"));
  const bridgedUSDC = structuredClone(monadQuote);
  (bridgedUSDC.details.currencyIn.currency as { address: string }).address = "0x" + "3".repeat(40);
  assert.throws(() => parseQuote(bridgedUSDC, owner, "monad", "20"));
  const wrongDestination = structuredClone(monadQuote);
  wrongDestination.details.currencyOut.currency.chainId = 999;
  assert.throws(() => parseQuote(wrongDestination, owner, "monad", "20"));
  const client = new RelayFunding("test-key", async (url, init) => {
    assert.equal(url, "https://api.relay.link/quote/v2");
    assert.deepEqual(JSON.parse(String(init?.body)), body);
    return Response.json(monadQuote);
  });
  const address = await client.address(owner, "monad");
  assert.equal(address.network, "monad");
  assert.equal(address.refundAddress, owner);
  assert.equal(address.reusable, true);
});
Deno.test("Ethereum and BNB deposit routes validate their distinct USDC contracts and decimals", () => {
  const ethereum = quoteBody(owner, "ethereum", "20");
  assert.equal(ethereum.originChainId, 1);
  assert.equal(ethereum.amount, "20000000");
  assert.equal(parseQuote(quote("ethereum", ethereum.amount), owner, "ethereum", "20").depositAddress, deposit);

  const bnb = quoteBody(owner, "bnb", "20");
  assert.equal(bnb.originChainId, 56);
  assert.equal(bnb.originCurrency, "0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d");
  assert.equal(bnb.amount, "20000000000000000000");
  assert.equal(amountUnits("1.123456", 18), "1123456000000000000");
  const bnbQuote = quote("bnb", bnb.amount);
  assert.equal(parseQuote(bnbQuote, owner, "bnb", "20").depositAddress, deposit);
  assert.throws(() => parseQuote(bnbQuote, owner, "ethereum", "20"));
  const wrongPrecision = structuredClone(bnbQuote);
  wrongPrecision.details.currencyIn.currency.decimals = 6;
  assert.throws(() => parseQuote(wrongPrecision, owner, "bnb", "20"));
  const wrongToken = structuredClone(bnbQuote);
  wrongToken.details.currencyIn.currency.address = networks.ethereum.token;
  assert.throws(() => parseQuote(wrongToken, owner, "bnb", "20"));
  assert.equal(Object.hasOwn(networks, "robinhood"), false);
});
Deno.test("wrong owner, EVM destination, spot asset and invalid source/steps cannot expose a QR", () => {
  const changes = [
    (q: any) => q.details.recipient = deposit,
    (q: any) => q.details.currencyOut.currency.chainId = 999,
    (q: any) => q.details.currencyOut.currency.address = "0x6d1e7cde53ba9467b783cb7c530ce054",
    (q: any) => q.details.currencyOut.currency.decimals = 6,
    (q: any) => q.details.currencyIn.amount = "200000000",
    (q: any) => q.details.currencyIn.currency.address = deposit,
    (q: any) => q.steps[0].depositAddress = owner,
    (q: any) => q.steps.push(q.steps[0]),
    (q: any) => q.details.currencyOut.minimumAmount = "0",
  ];
  for (const change of changes) { const q = quote(); change(q); assert.throws(() => parseQuote(q, owner, "arbitrum", "100")); }
});
Deno.test("unauthenticated, anonymous and disabled requests never call provider", async () => {
  const provider = new RelayFunding("key", () => { throw new Error("must not call"); });
  assert.equal((await handle(request("", "GET", undefined, "bad"), fixture(), config, provider)).status, 401);
  assert.equal((await handle(request(), fixture(true), config, provider)).status, 401);
  assert.deepEqual(await (await handle(request(), fixture(), { ...config, enabled: false }, provider)).json(), { available: false });
  assert.equal((await handle(request("/quote", "POST", { network: "arbitrum", amount: "100" }),
    fixture(), { ...config, enabled: false }, provider)).status, 503);
});
Deno.test("recipient injection and invalid body are rejected, owner comes from registry", async () => {
  let count = 0;
  const provider = new RelayFunding("key", async () => { count++; return Response.json(quote()); });
  for (const body of [{ network: "arbitrum", amount: "100", recipient: deposit },
      { network: "__proto__", amount: "100" }, { network: "base", amount: "-1" }]) {
    assert.equal((await handle(request("/quote", "POST", body), fixture(), config, provider)).status, 422);
  }
  assert.equal(count, 0);
  const response = await handle(request("/quote", "POST", { network: "arbitrum", amount: "100" }), fixture(), config, provider);
  assert.equal(response.status, 200); assert.equal((await response.json()).recipient, owner);
  assert.equal(response.headers.get("cache-control"), "no-store"); assert.equal(count, 1);
});
Deno.test("history validates recipient and distinguishes quoted and settled amounts", () => {
  const output = quote().details.currencyOut;
  const record = { id: "0x" + "a".repeat(64), recipient: owner, status: "success",
    createdAt: "2026-09-22T00:00:00Z", depositAddress: { address: deposit },
    data: { route: { quoted: { destination: { outputCurrency: output } } } } };
  assert.equal(parseDeposits({ requests: [record] }, owner)[0].amount, null);
  assert.equal(parseDeposits({ requests: [{ ...record, status: "new-status" }] }, owner)[0].status, "unknown");
  assert.throws(() => parseDeposits({ requests: [{ ...record, recipient: deposit }] }, owner));
  assert.throws(() => parseDeposits({ requests: [{ ...record, data: {} }] }, owner));
  const settled = { ...record, data: { route: { actual: { destination: { outputCurrency: output } } } } };
  assert.equal(parseDeposits({ requests: [settled] }, owner)[0].amount, "99.0");
});
Deno.test("history is scoped to bound owner and cannot forward arbitrary provider URLs", async () => {
  const provider = new RelayFunding("key", async (raw) => {
    const url = new URL(String(raw));
    assert.equal(url.origin, "https://api.relay.link"); assert.equal(url.pathname, "/requests/v3");
    assert.equal(url.searchParams.get("recipient"), owner);
    assert.equal(url.searchParams.get("destinationChainId"), "1337");
    return Response.json({ requests: [] });
  });
  assert.equal((await handle(request("/deposits?recipient=" + deposit), fixture(), config, provider)).status, 200);
});
Deno.test("provider failure remains unavailable and does not leak upstream content or keys", async () => {
  const provider = new RelayFunding("secret-test-key", async () => new Response("secret-test-key", { status: 429 }));
  const response = await handle(request("/deposits"), fixture(), config, provider);
  assert.equal(response.status, 503); assert.deepEqual(await response.json(), { error: "funding_unavailable" });
});

Deno.test("amount-free address registration keeps seed quote internal and fixes open perps route", async () => {
  let calls = 0;
  const provider = new RelayFunding("key", async (_url, init) => {
    calls++;
    const body = JSON.parse(String(init?.body));
    assert.equal(body.amount, "20000000");
    assert.equal(body.strict, false);
    assert.equal(body.recipient, owner);
    assert.equal(body.refundTo, owner);
    assert.equal(body.destinationCurrency, PERPS);
    const q = quote(); q.details.currencyIn.amount = "20000000";
    return Response.json(q);
  });
  for (const input of [{ network: "arbitrum", amount: "3" }, { network: "arbitrum", recipient: deposit },
    { network: "arbitrum", strict: true }, { network: "__proto__" }]) {
    assert.equal((await handle(request("/address", "POST", input), fixture(), config, provider)).status, 422);
  }
  assert.equal(calls, 0);
  assert.equal((await handle(request("/address", "POST", { network: "arbitrum" }), fixture(),
    { ...config, enabled: false }, provider)).status, 503);
  assert.equal((await handle(request("/address", "POST", { network: "arbitrum" }), fixture(true),
    config, provider)).status, 401);
  assert.equal(calls, 0);
  const response = await handle(request("/address", "POST", { network: "arbitrum" }), fixture(), config, provider);
  assert.equal(response.status, 200);
  const value = await response.json();
  assert.equal(value.reusable, true);
  assert.equal(value.depositAddress, deposit);
  assert.equal(value.recipient, owner);
  assert.equal(value.refundAddress, owner);
  assert.equal("estimatedOutput" in value, false);
  assert.equal("inputAmount" in value, false);
  assert.equal(calls, 1);
});

Deno.test("registered deposit address survives refresh without another Relay quote", async () => {
  const store: AddressStore = { rows: new Map() };
  const client = fixture(false, store);
  let calls = 0;
  const provider = new RelayFunding("key", async () => {
    calls++;
    const q = quote("arbitrum", "20000000");
    q.steps[0].depositAddress = "0x" + String(calls + 1).repeat(40);
    return Response.json(q);
  });
  const first = await handle(request("/address", "POST", { network: "arbitrum" }), client, config, provider);
  const second = await handle(request("/address", "POST", { network: "arbitrum" }), client, config, provider);
  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  assert.equal((await first.json()).depositAddress, (await second.json()).depositAddress);
  assert.equal(calls, 1);
  assert.equal(store.rows.size, 1);
});

Deno.test("each network has its own pinned, route-checked address", async () => {
  const store: AddressStore = { rows: new Map() };
  const client = fixture(false, store);
  let calls = 0;
  const provider = new RelayFunding("key", async (_url, init) => {
    calls++;
    const body = JSON.parse(String(init?.body));
    const network = body.originChainId === networks.base.chainId ? "base" : "arbitrum";
    const q = quote(network, "20000000");
    q.steps[0].depositAddress = network === "base" ? "0x" + "3".repeat(40) : deposit;
    return Response.json(q);
  });
  const address = async (network: "base" | "arbitrum") => {
    const response = await handle(request("/address", "POST", { network }), client, config, provider);
    assert.equal(response.status, 200);
    return (await response.json()).depositAddress;
  };
  assert.equal(await address("arbitrum"), deposit);
  assert.equal(await address("base"), "0x" + "3".repeat(40));
  assert.equal(await address("arbitrum"), deposit);
  assert.equal(await address("base"), "0x" + "3".repeat(40));
  assert.equal(calls, 2);
  assert.equal(store.rows.size, 2);
});

Deno.test("simultaneous first requests expose only the canonical persisted address", async () => {
  const store: AddressStore = { rows: new Map() };
  const client = fixture(false, store);
  let calls = 0;
  const provider = new RelayFunding("key", async () => {
    const number = ++calls;
    await new Promise(resolve => setTimeout(resolve, 5));
    const q = quote("arbitrum", "20000000");
    q.steps[0].depositAddress = "0x" + String(number + 1).repeat(40);
    return Response.json(q);
  });
  const [a, b] = await Promise.all([handle(request("/address", "POST", { network: "arbitrum" }), client, config, provider),
    handle(request("/address", "POST", { network: "arbitrum" }), client, config, provider)]);
  assert.equal(a.status, 200);
  assert.equal(b.status, 200);
  const first = await a.json(), second = await b.json();
  assert.equal(first.depositAddress, second.depositAddress);
  assert.equal(first.depositAddress, store.rows.values().next().value?.deposit_address);
  assert.equal(store.rows.size, 1);
});

Deno.test("storage errors or route mismatch never expose a fresh or corrupted address", async () => {
  let calls = 0;
  const provider = new RelayFunding("key", async () => { calls++; return Response.json(quote("arbitrum", "20000000")); });
  const broken: AddressStore = { rows: new Map(), writeError: true };
  const response = await handle(request("/address", "POST", { network: "arbitrum" }), fixture(false, broken), config, provider);
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: "funding_unavailable" });
  assert.equal(calls, 1);

  const unreadable: AddressStore = { rows: new Map(), readError: true };
  const readFailure = await handle(request("/address", "POST", { network: "arbitrum" }),
    fixture(false, unreadable), config, provider);
  assert.equal(readFailure.status, 503);
  assert.equal(calls, 1);

  const corrupted: AddressStore = { rows: new Map() };
  corrupted.rows.set([account, owner, "arbitrum"].join(":"), {
    account_id: account, wallet_address: owner, network: "arbitrum", origin_chain_id: 8453,
    origin_currency: networks.arbitrum.token, destination_chain_id: 1337,
    destination_currency: PERPS, deposit_address: deposit, request_id: "0x" + "a".repeat(64),
    created_at: "2026-09-23T00:00:00Z",
  });
  const mismatch = await handle(request("/address", "POST", { network: "arbitrum" }),
    fixture(false, corrupted), config, provider);
  assert.equal(mismatch.status, 503);
  assert.equal(calls, 1);
});

Deno.test("funding address migration protects and pins the first committed address", async () => {
  const db = new PGlite();
  try {
    await db.exec(`
      create role anon;
      create role authenticated;
      create role service_role bypassrls;
      create schema auth;
      create table auth.users(id uuid primary key);
      insert into auth.users values ('${account}');
    `);
    await db.exec(await Deno.readTextFile(
      new URL("../supabase/migrations/202609230004_funding_addresses.sql", import.meta.url),
    ));
    assert.equal((await db.query<{ rowsecurity: boolean }>(
      "select relrowsecurity as rowsecurity from pg_class where oid = 'public.bsmart_funding_addresses'::regclass",
    )).rows[0].rowsecurity, true);
    await db.exec("set role service_role");
    const fields = [account, owner, "arbitrum", 42161, networks.arbitrum.token, 1337, PERPS,
      deposit, "0x" + "a".repeat(64)];
    const insert = `insert into public.bsmart_funding_addresses
      (account_id,wallet_address,network,origin_chain_id,origin_currency,
       destination_chain_id,destination_currency,deposit_address,request_id)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9)`;
    await db.query(insert, fields);
    await db.query(insert + " on conflict do nothing",
      [...fields.slice(0, 7), "0x" + "3".repeat(40), fields[8]]);
    assert.equal((await db.query<{ deposit_address: string }>(
      "select deposit_address from public.bsmart_funding_addresses",
    )).rows[0].deposit_address, deposit);
    await assert.rejects(() => db.exec("update public.bsmart_funding_addresses set deposit_address = '0x" +
      "3".repeat(40) + "'"));
    await db.exec("reset role; set role authenticated");
    await assert.rejects(() => db.exec("select * from public.bsmart_funding_addresses"));
    await assert.rejects(() => db.query(insert, fields));
    await db.exec("reset role; set role anon");
    await assert.rejects(() => db.exec("select * from public.bsmart_funding_addresses"));
  } finally { await db.close(); }
});
