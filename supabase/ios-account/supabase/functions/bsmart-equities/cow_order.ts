import { setGlobalAdapter } from "npm:@cowprotocol/sdk-common@0.14.2";
import { ContractsOrderKind, OrderBalance } from "npm:@cowprotocol/sdk-contracts-ts@3.7.2";
import { OrderSigningUtils } from "npm:@cowprotocol/sdk-order-signing@1.1.15";
import { ViemAdapter } from "npm:@cowprotocol/sdk-viem-adapter@0.3.33";
import { createPublicClient, custom, recoverTypedDataAddress, type TypedDataDomain } from "npm:viem@2.56.3";
import { MarketError, object } from "../bsmart-markets/routing.ts";
import { NETWORKS } from "./assets.ts";
import { intentId, refreshable, type IntentRow } from "./intents.ts";
import { APP_DATA, address, atoms, cowQuoteFingerprint, type CowQuoteMaterial, type ChainState, raw, validateState } from "./quote.ts";

// Official SDK utilities only: no signer and a transport that cannot access a chain.
const adapter = new ViemAdapter({ provider: createPublicClient({ transport: custom({
  request: () => Promise.reject(new Error("cow_codec_offline_only")),
}) }) });
setGlobalAdapter(adapter);

export type PreparedCowOrder = {
  schema: "cow_order_v1"; intentId: string; intentVersion: number; account: string;
  fingerprint: string; owner: string; instrument: CowQuoteMaterial["instrument"];
  side: "buy" | "sell"; order: CowQuoteMaterial["order"]; domain: CowQuoteMaterial["domain"];
  orderUid: string; orderDigest: string; expiresAt: string;
};
const invalid = () => new MarketError("cow_order_binding_invalid", 409);
function keys(value: unknown, fields: string[]): Record<string, unknown> {
  const r = object(value);
  if (Object.keys(r).length !== fields.length || fields.some(k => !Object.hasOwn(r, k))) throw invalid();
  return r;
}
function equalFields(a: unknown, b: unknown, fields: string[]) {
  const left = keys(a, fields), right = keys(b, fields);
  if (fields.some(k => left[k] !== right[k])) throw invalid();
}
const orderFields = ["sellToken", "buyToken", "receiver", "sellAmount", "buyAmount", "validTo", "appData",
  "feeAmount", "kind", "partiallyFillable", "sellTokenBalance", "buyTokenBalance"];
const domainFields = ["name", "version", "chainId", "verifyingContract"];
const instrumentFields = ["assetId", "symbol", "network", "chainId", "token", "usdc", "tokenVariant", "maxLeverage"];

async function identity(order: PreparedCowOrder["order"], domain: PreparedCowOrder["domain"],
  instrument: PreparedCowOrder["instrument"], owner: string, side: "buy" | "sell") {
  keys(order, orderFields); keys(instrument, instrumentFields);
  if (!["buy", "sell"].includes(side) || !["Ethereum", "Ink"].includes(instrument.network)) throw invalid();
  const config = NETWORKS[instrument.network];
  if (instrument.chainId !== config.chainId || instrument.usdc !== config.usdc || instrument.tokenVariant !== "raw" ||
    instrument.maxLeverage !== 1 || address(instrument.token) !== instrument.token || instrument.token === instrument.usdc ||
    address(owner) !== owner || order.receiver !== owner || order.kind !== "sell" || order.partiallyFillable !== false ||
    order.sellTokenBalance !== "erc20" || order.buyTokenBalance !== "erc20" || order.feeAmount !== "0" || order.appData !== APP_DATA ||
    order.sellToken !== (side === "buy" ? instrument.usdc : instrument.token) ||
    order.buyToken !== (side === "buy" ? instrument.token : instrument.usdc) ||
    !Number.isInteger(order.validTo) || order.validTo <= 0 || order.validTo > 4294967295) throw invalid();
  raw(order.sellAmount, true); raw(order.buyAmount, true);
  equalFields(domain, await OrderSigningUtils.getDomain(instrument.chainId), domainFields);
  // Never permit client-selected SDK environment or settlement overrides.
  return await OrderSigningUtils.generateOrderId(instrument.chainId, { ...order, kind: ContractsOrderKind.SELL,
    sellTokenBalance: OrderBalance.ERC20, buyTokenBalance: OrderBalance.ERC20 }, { owner });
}

// Consumes private material from validateQuoteArtifacts and a server-read intent.
// This is NOT an authorization, reservation, ledger mutation or submission.
export async function prepareCowOrder(material: CowQuoteMaterial, row: IntentRow,
  expectedVersion: number, latest: ChainState, now: number, currentBoundOwner: string): Promise<PreparedCowOrder> {
  if (address(currentBoundOwner) !== material.owner) throw new MarketError("wallet_changed", 409);
  refreshable(row, material.owner, expectedVersion);
  if (row.state !== "quoted" || row.account_id !== material.account || !row.preview || material.version !== 1 ||
    row.input.ticker !== row.preview.ticker || row.input.side !== row.preview.side ||
    !Number.isFinite(now) || !row.quote_expires_at || !Number.isFinite(Date.parse(row.quote_expires_at)) || Date.parse(row.quote_expires_at) <= now + 5000 ||
    !Number.isFinite(material.expiresAt) || material.expiresAt <= now + 5000 ||
    material.expiresAt > now + 600_000 || material.order.validTo * 1000 <= now + 5000 ||
    material.expiresAt > material.order.validTo * 1000) throw invalid();
  keys(material, ["version", "account", "owner", "instrument", "input", "order", "domain", "quote", "expiresAt", "block", "multiplier", "multiplierNonce"]);
  equalFields(material.input, row.input, Object.keys(row.input));
  keys(material.quote, ["id", "verified", "networkFeeAmountRaw", "protocolFeeBps", "quotedOutputAmountRaw"]);
  if (!Number.isSafeInteger(material.quote.id) || material.quote.id < 0 || material.quote.verified !== true) {
    throw new MarketError("quote_unverified", 409);
  }
  const fingerprint = await cowQuoteFingerprint(material);
  const candidates = row.preview.candidates.filter(c => c.fingerprint === fingerprint);
  if (candidates.length !== 1) throw invalid();
  const c = candidates[0];
  equalFields(c.instrument, material.instrument, instrumentFields);
  if (c.owner !== material.owner || c.receiver !== material.owner || c.providerVerified !== true || c.executable !== false ||
    c.inputAmountRaw !== material.order.sellAmount || c.minimumOutputAmountRaw !== material.order.buyAmount ||
    c.quotedOutputAmountRaw !== material.quote.quotedOutputAmountRaw || c.estimatedNetworkFeeAmountRaw !== material.quote.networkFeeAmountRaw ||
    c.protocolFeeBps !== material.quote.protocolFeeBps || c.stateBlock !== material.block || c.multiplierRaw !== material.multiplier ||
    Date.parse(c.expiresAt) !== material.expiresAt || !Number.isFinite(Date.parse(c.observedAt)) ||
    Date.parse(c.observedAt) > now || now - Date.parse(c.observedAt) >= 30_000) throw invalid();
  validateState(latest, material.instrument, material.owner, now);
  if (latest.multiplier !== material.multiplier || latest.multiplierNonce !== material.multiplierNonce ||
    BigInt(latest.block) < BigInt(raw(material.block, true))) throw new MarketError("corporate_action_changed", 409);
  const buy = row.input.side === "buy", amount = atoms(row.input.amount, buy ? 6 : latest.tokenDecimals);
  if (amount !== material.order.sellAmount || c.inputDecimals !== (buy ? 6 : latest.tokenDecimals) ||
    c.outputDecimals !== (buy ? latest.tokenDecimals : 6)) throw invalid();
  if (BigInt(buy ? latest.usdcBalance : latest.tokenBalance) < BigInt(amount)) throw new MarketError("funding_required", 409);
  if (BigInt(buy ? latest.usdcAllowance : latest.tokenAllowance) < BigInt(amount)) throw new MarketError("approval_required", 409);
  const { orderId, orderDigest } = await identity(material.order, material.domain, material.instrument, material.owner, row.input.side);
  return structuredClone({ schema: "cow_order_v1", intentId: intentId(row.id), intentVersion: expectedVersion,
    account: intentId(row.account_id), fingerprint, owner: material.owner, instrument: material.instrument,
    side: row.input.side, order: material.order, domain: material.domain, orderUid: orderId.toLowerCase(),
    orderDigest: orderDigest.toLowerCase(), expiresAt: new Date(material.expiresAt).toISOString() });
}

export async function assertPreparedCowOrder(p: PreparedCowOrder) {
  keys(p, ["schema", "intentId", "intentVersion", "account", "fingerprint", "owner", "instrument", "side", "order", "domain", "orderUid", "orderDigest", "expiresAt"]);
  intentId(p.intentId); intentId(p.account);
  if (p.schema !== "cow_order_v1" || !Number.isInteger(p.intentVersion) || p.intentVersion < 0 ||
    p.intentVersion > 2147483646 || !/^[0-9a-f]{64}$/.test(p.fingerprint) || !Number.isFinite(Date.parse(p.expiresAt)) ||
    Date.parse(p.expiresAt) > p.order.validTo * 1000) throw invalid();
  const { orderId, orderDigest } = await identity(p.order, p.domain, p.instrument, p.owner, p.side);
  if (p.orderUid !== orderId.toLowerCase() || p.orderDigest !== orderDigest.toLowerCase()) throw invalid();
}
export function cowTypedData(p: PreparedCowOrder) {
  return { domain: structuredClone(p.domain), types: structuredClone(OrderSigningUtils.getEIP712Types()),
    primaryType: "Order" as const, message: structuredClone(p.order) };
}
export function validateCowTypedData(p: PreparedCowOrder, value: unknown) {
  const r = keys(value, ["domain", "types", "primaryType", "message"]);
  equalFields(r.domain, p.domain, domainFields); equalFields(r.message, p.order, orderFields);
  const types = keys(r.types, ["Order"]), expected = OrderSigningUtils.getEIP712Types().Order;
  if (r.primaryType !== "Order" || !Array.isArray(types.Order) || types.Order.length !== expected.length) throw invalid();
  types.Order.forEach((field, n) => equalFields(field, expected[n], ["name", "type"]));
}
export async function verifyCowSignature(p: PreparedCowOrder, signature: unknown, now: number) {
  await assertPreparedCowOrder(p);
  if (!Number.isFinite(now) || Date.parse(p.expiresAt) <= now + 5000 || p.order.validTo * 1000 <= now + 5000) {
    throw new MarketError("quote_expired", 409);
  }
  // V1 only accepts EIP-712 EOA signatures. No eth_sign fallback or EIP-1271 guess.
  if (typeof signature !== "string" || !/^0x[0-9a-fA-F]{130}$/.test(signature)) throw new MarketError("cow_signature_invalid", 422);
  try {
    const typed = cowTypedData(p);
    const recovered = await recoverTypedDataAddress({ ...typed, domain: typed.domain as TypedDataDomain, signature: signature as `0x${string}` });
    if (address(recovered) !== p.owner) throw Error("wrong_owner");
  } catch { throw new MarketError("cow_signature_invalid", 422); }
  return { orderUid: p.orderUid, owner: p.owner, signingScheme: "eip712" as const };
}

// Crypto verification alone does not bind an intent. Future authorization workers
// must supply newly read server context, not a client-provided prepared object.
export async function verifyBoundCowSignature(p: PreparedCowOrder, material: CowQuoteMaterial, row: IntentRow,
  expectedVersion: number, latest: ChainState, signature: unknown, now: number, currentBoundOwner: string) {
  const current = await prepareCowOrder(material, row, expectedVersion, latest, now, currentBoundOwner);
  const given = keys(p, Object.keys(current)), expected = current as unknown as Record<string, unknown>;
  if (Object.keys(current).filter(k => !["order", "domain", "instrument"].includes(k)).some(k => given[k] !== expected[k])) throw invalid();
  equalFields(p.order, current.order, orderFields); equalFields(p.domain, current.domain, domainFields);
  equalFields(p.instrument, current.instrument, instrumentFields);
  return await verifyCowSignature(current, signature, now);
}
