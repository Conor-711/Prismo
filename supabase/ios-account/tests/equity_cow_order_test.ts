import { strict as assert } from "node:assert";
import { hashTypedData, type TypedDataDomain, type Hex } from "npm:viem@2.56.3";
import { privateKeyToAccount } from "npm:viem@2.56.3/accounts";
import { OrderSigningUtils } from "npm:@cowprotocol/sdk-order-signing@1.1.15";
import { ContractsOrderKind, OrderBalance } from "npm:@cowprotocol/sdk-contracts-ts@3.7.2";
import { assertPreparedCowOrder, cowTypedData, prepareCowOrder, validateCowTypedData, verifyBoundCowSignature, verifyCowSignature } from "../supabase/functions/bsmart-equities/cow_order.ts";
import { cowQuoteFingerprint, validateQuote } from "../supabase/functions/bsmart-equities/quote.ts";
import { at, context, owner, signer } from "./fixtures/equity_cow.ts";

Deno.test("CoW canonical material uses one quote validator and is absent from public preview", async () => {
  const c = await context();
  assert.deepEqual(c.preview, await validateQuote(c.response, c.request, c.instrument, c.input, c.state, c.row.account_id, at));
  assert.equal(c.material.order.feeAmount, "0"); assert.equal(c.material.order.sellAmount, "100000000");
  assert.equal(c.material.order.buyAmount, c.preview.minimumOutputAmountRaw);
  for (const field of ["order", "domain", "material", "orderUid", "signature"]) assert.equal(Object.hasOwn(c.preview, field), false);
});
Deno.test("CoW quote fingerprint is stable across jsonb property ordering", async () => {
  const c = await context();
  const reverse = (value: unknown): unknown => value && typeof value === "object" && !Array.isArray(value)
    ? Object.fromEntries(Object.entries(value).reverse().map(([k, v]) => [k, reverse(v)])) : value;
  assert.equal(await cowQuoteFingerprint(reverse(c.material) as typeof c.material), c.preview.fingerprint);
});
Deno.test("CoW UID and digest come from official SDK and agree with viem EIP712", async () => {
  for (const network of ["Ethereum", "Ink"] as const) {
    const { prepared: p } = await context("buy", network), typed = cowTypedData(p);
    const sdk = await OrderSigningUtils.generateOrderId(p.instrument.chainId, { ...p.order, kind: ContractsOrderKind.SELL,
      sellTokenBalance: OrderBalance.ERC20, buyTokenBalance: OrderBalance.ERC20 }, { owner });
    assert.equal(p.orderUid, sdk.orderId.toLowerCase());
    assert.equal(p.orderDigest, hashTypedData({ ...typed, domain: typed.domain as TypedDataDomain }));
    assert.match(p.orderUid, /^0x[0-9a-f]{112}$/); await assertPreparedCowOrder(p);
  }
});
Deno.test("CoW preparation binds private quote to one account, intent version and saved candidate", async () => {
  const c = await context();
  for (const row of [{ ...c.row, account_id: "22345678-1234-1234-1234-123456789abc" }, { ...c.row, version: 2 },
    { ...c.row, wallet_address: c.instrument.token }, { ...c.row, state: "cancelled" as const },
    { ...c.row, preview: null }, { ...c.row, quote_expires_at: "not-a-time" }, { ...c.row, input: { ...c.input, slippageBps: 100 } }]) {
    await assert.rejects(() => prepareCowOrder(c.material, row, 1, c.state, at, owner));
  }
  const absent = structuredClone(c.row); absent.preview!.candidates[0].fingerprint = "aa".repeat(32);
  await assert.rejects(() => prepareCowOrder(c.material, absent, 1, c.state, at, owner));
  const duplicates = structuredClone(c.row); duplicates.preview!.candidates.push(c.preview);
  await assert.rejects(() => prepareCowOrder(c.material, duplicates, 1, c.state, at, owner));
});
Deno.test("CoW preparation rejects unverified, expired and stale chain quotes", async () => {
  const c = await context();
  await assert.rejects(() => prepareCowOrder({ ...c.material, quote: { ...c.material.quote, verified: false } }, c.row, 1, c.state, at, owner));
  await assert.rejects(() => prepareCowOrder(c.material, c.row, 1, c.state, at + 55_000, owner));
  await assert.rejects(() => prepareCowOrder(c.material, c.row, 1, { ...c.state, at: at + 30_000 }, at + 30_000, owner));
  await assert.rejects(() => prepareCowOrder(c.material, c.row, 1, { ...c.state, at: at - 30_000 }, at, owner));
});
Deno.test("CoW preparation rechecks spendable balance, exact allowance, rebase nonce and current block", async () => {
  const c = await context();
  for (const patch of [{ usdcBalance: "99999999" }, { usdcAllowance: "99999999" }, { multiplier: "1200000000000000000" },
    { multiplierNonce: "2" }, { block: "23999999" }, { tokenDecimals: 17 }, { chainId: 57073 }, { owner: c.instrument.token },
    { activationTime: at / 1000 + 300 }]) {
    await assert.rejects(() => prepareCowOrder(c.material, c.row, 1, { ...c.state, ...patch }, at, owner));
  }
  const sell = await context("sell");
  for (const patch of [{ tokenBalance: "999999999999999999" }, { tokenAllowance: "0" }]) {
    await assert.rejects(() => prepareCowOrder(sell.material, sell.row, 1, { ...sell.state, ...patch }, at, owner));
  }
});
Deno.test("CoW private material cannot gain hooks, alternate spender or hidden signature fields", async () => {
  const c = await context();
  for (const material of [{ ...c.material, signature: "hidden" },
    { ...c.material, order: { ...c.material.order, preInteractions: [] } },
    { ...c.material, order: { ...c.material.order, receiver: c.instrument.token } },
    { ...c.material, domain: { ...c.material.domain, verifyingContract: c.instrument.token } }]) {
    await assert.rejects(() => prepareCowOrder(material, c.row, 1, c.state, at, owner));
  }
});
Deno.test("CoW dedicated typed-data codec rejects substitution and does not accept arbitrary EIP712", async () => {
  const { prepared: p } = await context(), typed = cowTypedData(p);
  validateCowTypedData(p, typed);
  const changes = [{ domain: { ...typed.domain, chainId: 57073 } }, { domain: { ...typed.domain, name: "Fake Protocol" } },
    { domain: { ...typed.domain, salt: "0x00" } }, { message: { ...typed.message, sellAmount: "100000001" } },
    { message: { ...typed.message, buyAmount: "1" } }, { message: { ...typed.message, feeAmount: "1" } },
    { message: { ...typed.message, partiallyFillable: true } }, { message: { ...typed.message, appData: "0x" + "11".repeat(32) } },
    { message: { ...typed.message, buyTokenBalance: "internal" } }, { primaryType: "Permit" },
    { types: { ...typed.types, Permit: [] } }, { types: { Order: [...typed.types.Order].reverse() } }];
  for (const patch of changes) assert.throws(() => validateCowTypedData(p, { ...typed, ...patch }));
  const mutated = cowTypedData(p); mutated.types.Order[0].type = "bytes32";
  assert.throws(() => validateCowTypedData(p, mutated));
  assert.equal(cowTypedData(p).types.Order[0].type, "address");
});
Deno.test("CoW signature verifier recovers the exact owner and never signs or submits", async () => {
  const { prepared: p } = await context(), typed = cowTypedData(p);
  const signature = await signer.signTypedData({ ...typed, domain: typed.domain as TypedDataDomain });
  assert.deepEqual(await verifyCowSignature(p, signature, at), { orderUid: p.orderUid, owner, signingScheme: "eip712" });
  const other = privateKeyToAccount("0x" + "0".repeat(63) + "2" as Hex);
  await assert.rejects(() => verifyCowSignature(p, other.signTypedData, at));
  await assert.rejects(() => verifyCowSignature(p, "0x1234", at));
  await assert.rejects(() => verifyCowSignature(p, "0x" + "00".repeat(65), at));
  await assert.rejects(() => verifyCowSignature(p, signature, at + 55_000));
  const otherSignature = await other.signTypedData({ ...typed, domain: typed.domain as TypedDataDomain });
  await assert.rejects(() => verifyCowSignature(p, otherSignature, at));
});
Deno.test("CoW UID integrity rejects altered order, domain, chain, side and digest in recovery", async () => {
  const { prepared: p } = await context();
  for (const patch of [{ orderUid: "0x" + "11".repeat(56) }, { orderDigest: "0x" + "11".repeat(32) },
    { order: { ...p.order, buyAmount: "1" } }, { domain: { ...p.domain, chainId: 57073 } }, { side: "sell" as const },
    { instrument: { ...p.instrument, chainId: 57073 } }, { intentVersion: -1 }]) {
    await assert.rejects(() => assertPreparedCowOrder({ ...p, ...patch }));
  }
});
Deno.test("CoW EIP712 verification rejects eth_sign fallback and signatures over substituted domains or limits", async () => {
  const { prepared: p } = await context(), typed = cowTypedData(p);
  const personal = await signer.signMessage({ message: { raw: p.orderDigest as Hex } });
  await assert.rejects(() => verifyCowSignature(p, personal, at));
  for (const altered of [{ ...typed, domain: { ...typed.domain, chainId: 57073 } },
    { ...typed, message: { ...typed.message, sellAmount: "100000001" } },
    { ...typed, message: { ...typed.message, buyAmount: "1" } }]) {
    const signature = await signer.signTypedData({ ...altered, domain: altered.domain as TypedDataDomain });
    await assert.rejects(() => verifyCowSignature(p, signature, at));
  }
});
Deno.test("CoW bound signature revalidates intent context and funds after wallet signing", async () => {
  const c = await context(), typed = cowTypedData(c.prepared);
  const signature = await signer.signTypedData({ ...typed, domain: typed.domain as TypedDataDomain });
  await verifyBoundCowSignature(structuredClone(c.prepared), c.material, c.row, 1, c.state, signature, at, owner);
  await assert.rejects(() => verifyBoundCowSignature(c.prepared, c.material, { ...c.row, version: 2 }, 1, c.state, signature, at, owner));
  await assert.rejects(() => verifyBoundCowSignature(c.prepared, c.material, c.row, 1, { ...c.state, usdcBalance: "0" }, signature, at, owner));
  await assert.rejects(() => verifyBoundCowSignature({ ...c.prepared, intentId: "22345678-1234-1234-1234-123456789abc" },
    c.material, c.row, 1, c.state, signature, at, owner));
  await assert.rejects(() => verifyBoundCowSignature(c.prepared, c.material, c.row, 1, c.state, signature, at, c.instrument.token));
});
Deno.test("CoW same payload across different intent IDs has one UID, requiring permanent provider UID deduplication", async () => {
  const c = await context(), secondId = "22345678-1234-1234-1234-123456789abc";
  const second = await prepareCowOrder(c.material, { ...c.row, id: secondId }, 1, c.state, at, owner);
  assert.equal(second.orderUid, c.prepared.orderUid); assert.notEqual(second.intentId, c.prepared.intentId);
  const migration = await Deno.readTextFile(new URL("../supabase/migrations/202610010005_equity_intent_ledger.sql", import.meta.url));
  assert.ok(migration.includes("unique(provider,source_network,provider_id)"));
});
Deno.test("CoW synthetic fixture matches SDK vectors and confirmed evidence, not live orders", async () => {
  const fixture = JSON.parse(await Deno.readTextFile(new URL("../../../contracts/fixtures/evm-equity-cow-codec.json", import.meta.url)));
  assert.equal(fixture.synthetic, true); assert.equal(fixture.signaturesIncluded, false); assert.equal(fixture.networkCalls, false);
  assert.deepEqual((await context()).prepared, fixture.examples.buyPreparation);
  assert.deepEqual((await context("sell")).prepared, fixture.examples.sellPreparation);
});
