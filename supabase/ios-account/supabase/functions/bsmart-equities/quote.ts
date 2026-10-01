import { BuyTokenDestination, getQuoteAmountsAndCosts, OrderKind, OrderQuoteSideKindSell, type OrderParameters, PriceQuality, SellTokenSource, SigningScheme } from "npm:@cowprotocol/sdk-order-book@4.2.1";
import { OrderSigningUtils } from "npm:@cowprotocol/sdk-order-signing@1.1.15";
import { parseUnits } from "npm:viem@2.56.3";
import { MarketError, object, tickerInput } from "../bsmart-markets/routing.ts";
import { NETWORKS } from "./assets.ts";
import type { EVMInstrument } from "./routing.ts";

export type PreviewInput = { ticker: string; side: "buy" | "sell"; amount: string;
  slippageBps: number; maxNetworkFeeBps: number; minimumOutput?: string };
export type ChainState = { at: number; chainId: number; owner: string; token: string; usdc: string;
  block: string; blockTimestamp: number; tokenDecimals: number; usdcDecimals: number;
  tokenBalance: string; usdcBalance: string; tokenAllowance: string; usdcAllowance: string;
  multiplier: string; multiplierNonce: string; activationTime: number };
export const APP_DATA = "0x" + "00".repeat(32);
export const ORDER_LIFETIME_SECONDS = 300;
const invalid = () => new MarketError("invalid_quote");
const decimal = /^(0|[1-9][0-9]{0,20})(\.[0-9]{1,18})?$/;
export function address(value: unknown): string {
  if (typeof value !== "string" || !/^0x[0-9a-fA-F]{40}$/.test(value) || /^0x0{40}$/i.test(value)) throw invalid();
  return value.toLowerCase();
}
export function raw(value: unknown, positive = false): string {
  if (typeof value !== "string" || !/^(0|[1-9][0-9]{0,77})$/.test(value) || BigInt(value) >= 2n ** 256n || positive && BigInt(value) === 0n) throw invalid();
  return value;
}
export function previewInput(value: unknown): PreviewInput {
  let v: Record<string, unknown>;
  try { v = object(value); } catch { throw new MarketError("invalid_preview", 422); }
  if (Object.keys(v).some(k => !["ticker", "side", "amount", "slippageBps", "maxNetworkFeeBps", "minimumOutput"].includes(k)) ||
    typeof v.ticker !== "string" || !["buy", "sell"].includes(v.side as string) || typeof v.amount !== "string" || !decimal.test(v.amount) ||
    /^0(\.0+)?$/.test(v.amount) || !Number.isInteger(v.slippageBps) || !Number.isInteger(v.maxNetworkFeeBps) ||
    (v.slippageBps as number) < 0 || (v.slippageBps as number) > 1000 || (v.maxNetworkFeeBps as number) < 0 || (v.maxNetworkFeeBps as number) > 1000 ||
    v.minimumOutput !== undefined && (typeof v.minimumOutput !== "string" || !decimal.test(v.minimumOutput) || /^0(\.0+)?$/.test(v.minimumOutput))) {
    throw new MarketError("invalid_preview", 422);
  }
  return { ticker: tickerInput(v.ticker), side: v.side as PreviewInput["side"], amount: v.amount,
    slippageBps: v.slippageBps as number, maxNetworkFeeBps: v.maxNetworkFeeBps as number,
    ...(v.minimumOutput === undefined ? {} : { minimumOutput: v.minimumOutput as string }) };
}
export function atoms(value: string, decimals: number): string {
  if (!decimal.test(value) || !Number.isInteger(decimals) || decimals < 0 || decimals > 18 ||
    (value.split(".")[1]?.length ?? 0) > decimals) throw new MarketError("invalid_precision", 422);
  return raw(parseUnits(value, decimals).toString(), true);
}
export function validateState(s: ChainState, i: EVMInstrument, owner: string, now: number): void {
  if (s.chainId !== i.chainId || address(s.owner) !== owner || address(s.token) !== i.token || address(s.usdc) !== i.usdc ||
    s.usdcDecimals !== 6 || !Number.isInteger(s.tokenDecimals) || s.tokenDecimals < 0 || s.tokenDecimals > 18 ||
    !Number.isFinite(s.at) || now < s.at || now - s.at >= 30_000 || !Number.isSafeInteger(s.blockTimestamp) ||
    now / 1000 < s.blockTimestamp || now / 1000 - s.blockTimestamp > 120 || !Number.isSafeInteger(s.activationTime) || s.activationTime < 0) throw invalid();
  raw(s.block, true); raw(s.multiplier, true); raw(s.multiplierNonce);
  for (const amount of [s.tokenBalance, s.usdcBalance, s.tokenAllowance, s.usdcAllowance]) raw(amount);
  // Include the entire order lifetime in the issuer-recommended +/-15 minute window.
  const seconds = now / 1000;
  if (s.activationTime && s.activationTime >= seconds - 900 && s.activationTime <= seconds + 900 + ORDER_LIFETIME_SECONDS) {
    throw new MarketError("corporate_action_window");
  }
}
export function quoteRequest(i: EVMInstrument, owner: string, input: PreviewInput, state: ChainState, now: number) {
  validateState(state, i, owner, now);
  const sellDecimals = input.side === "buy" ? 6 : state.tokenDecimals;
  const amount = atoms(input.amount, sellDecimals);
  if (input.side === "buy" && BigInt(amount) > 100_000_000_000n) throw new MarketError("amount_too_large", 422);
  if (input.side === "sell" && BigInt(amount) > BigInt(state.tokenBalance)) throw new MarketError("insufficient_owned_token", 409);
  return { sellToken: input.side === "buy" ? i.usdc : i.token, buyToken: input.side === "buy" ? i.token : i.usdc,
    from: owner, receiver: owner, sellAmountBeforeFee: amount, kind: OrderQuoteSideKindSell.SELL,
    sellTokenBalance: SellTokenSource.ERC20, buyTokenBalance: BuyTokenDestination.ERC20, signingScheme: SigningScheme.EIP712,
    appData: APP_DATA, validTo: Math.floor(now / 1000) + ORDER_LIFETIME_SECONDS, priceQuality: PriceQuality.OPTIMAL,
    timeout: i.network === "Ink" ? 2500 : 1800 };
}
export type QuoteRequest = ReturnType<typeof quoteRequest>;
export type CowQuoteMaterial = {
  version: 1; account: string; owner: string; instrument: EVMInstrument; input: PreviewInput;
  order: OrderParameters & { receiver: string; appData: string }; domain: Awaited<ReturnType<typeof OrderSigningUtils.getDomain>>;
  quote: { id: number; verified: boolean; networkFeeAmountRaw: string; protocolFeeBps: number; quotedOutputAmountRaw: string };
  expiresAt: number; block: string; multiplier: string; multiplierNonce: string;
};
export async function cowQuoteFingerprint(material: CowQuoteMaterial) {
  // Explicit ordering survives a future jsonb round trip. Extra signing fields are
  // rejected by the preparation codec, never silently included in an authorization.
  const { instrument: i, order: o, domain: d, quote: q } = material;
  const canonical = { version: material.version, account: material.account, owner: material.owner,
    instrument: { assetId: i.assetId, symbol: i.symbol, network: i.network, chainId: i.chainId,
      token: i.token, usdc: i.usdc, tokenVariant: i.tokenVariant, maxLeverage: i.maxLeverage },
    input: previewInput(material.input),
    order: { sellToken: o.sellToken, buyToken: o.buyToken, receiver: o.receiver,
      sellAmount: o.sellAmount, buyAmount: o.buyAmount, feeAmount: o.feeAmount, kind: o.kind,
      validTo: o.validTo, appData: o.appData, partiallyFillable: o.partiallyFillable,
      sellTokenBalance: o.sellTokenBalance, buyTokenBalance: o.buyTokenBalance },
    domain: { name: d.name, version: d.version, chainId: d.chainId, verifyingContract: d.verifyingContract },
    quote: { id: q.id, verified: q.verified, networkFeeAmountRaw: q.networkFeeAmountRaw,
      protocolFeeBps: q.protocolFeeBps, quotedOutputAmountRaw: q.quotedOutputAmountRaw },
    expiresAt: material.expiresAt, block: material.block, multiplier: material.multiplier, multiplierNonce: material.multiplierNonce };
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(canonical))))]
    .map(b => b.toString(16).padStart(2, "0")).join("");
}
// Private canonical material stays separate from the public preview projection.
export async function validateQuoteArtifacts(value: unknown, request: QuoteRequest, i: EVMInstrument,
  input: PreviewInput, state: ChainState, account: string, now: number) {
  validateState(state, i, request.from, now);
  const r = object(value), q = object(r.quote);
  if (NETWORKS[i.network].chainId !== i.chainId || NETWORKS[i.network].usdc !== i.usdc || i.tokenVariant !== "raw" ||
    address(r.from) !== request.from || address(q.receiver) !== request.from ||
    address(q.sellToken) !== request.sellToken || address(q.buyToken) !== request.buyToken ||
    q.kind !== "sell" || q.partiallyFillable !== false || q.sellTokenBalance !== "erc20" || q.buyTokenBalance !== "erc20" ||
    q.appData !== APP_DATA || q.appDataHash !== undefined && q.appDataHash !== APP_DATA ||
    q.signingScheme !== undefined && q.signingScheme !== "eip712" || q.validTo !== request.validTo ||
    typeof r.verified !== "boolean" || typeof r.expiration !== "string" || !/^\d{4}-\d\d-\d\dT.*Z$/.test(r.expiration) ||
    !Number.isSafeInteger(r.id) || (r.id as number) < 0) throw invalid();
  const expiry = Date.parse(r.expiration);
  if (!Number.isFinite(expiry) || expiry <= now + 5000 || expiry > now + 600_000 || request.validTo * 1000 <= now + 5000) throw new MarketError("quote_expired");
  const sell = raw(q.sellAmount, true), buy = raw(q.buyAmount, true), fee = raw(q.feeAmount);
  if (BigInt(sell) + BigInt(fee) !== BigInt(request.sellAmountBeforeFee)) throw invalid();
  if (BigInt(fee) * 10_000n > BigInt(request.sellAmountBeforeFee) * BigInt(input.maxNetworkFeeBps)) throw new MarketError("network_fee_limit");
  const protocol = r.protocolFeeBps ?? "0";
  if (typeof protocol !== "string" || !/^(0|[1-9][0-9]{0,3})$/.test(protocol) || Number(protocol) >= 10_000) throw invalid();
  // Use SDK fee/slippage math: modern orders include network costs in sellAmount and sign feeAmount=0.
  const parameters = { sellToken: request.sellToken, buyToken: request.buyToken, receiver: request.from,
    sellAmount: sell, buyAmount: buy, feeAmount: fee, kind: OrderKind.SELL,
    validTo: request.validTo, appData: APP_DATA, partiallyFillable: false,
    sellTokenBalance: request.sellTokenBalance, buyTokenBalance: request.buyTokenBalance } as OrderParameters;
  const amounts = getQuoteAmountsAndCosts({ orderParams: parameters, protocolFeeBps: Number(protocol),
    partnerFeeBps: 0, slippagePercentBps: input.slippageBps });
  let minimum = amounts.amountsToSign.buyAmount;
  const outputDecimals = input.side === "buy" ? state.tokenDecimals : 6;
  if (input.minimumOutput) {
    const floor = BigInt(atoms(input.minimumOutput, outputDecimals));
    if (floor > BigInt(buy)) throw new MarketError("minimum_output_unavailable");
    if (floor > minimum) minimum = floor;
  }
  if (minimum <= 0n || amounts.amountsToSign.sellAmount !== BigInt(request.sellAmountBeforeFee)) throw invalid();
  const order = { ...parameters, receiver: request.from, appData: APP_DATA, sellAmount: raw(amounts.amountsToSign.sellAmount.toString(), true),
    buyAmount: raw(minimum.toString(), true), feeAmount: "0" };
  const domain = await OrderSigningUtils.getDomain(i.chainId);
  if (domain.chainId !== i.chainId || address(domain.verifyingContract) === request.from) throw invalid();
  const material: CowQuoteMaterial = {
    version: 1, account, owner: request.from, instrument: i, input, order, domain,
    quote: { id: r.id as number, verified: r.verified, networkFeeAmountRaw: fee, protocolFeeBps: Number(protocol), quotedOutputAmountRaw: buy },
    expiresAt: Math.min(expiry, request.validTo * 1000), block: state.block,
    multiplier: state.multiplier, multiplierNonce: state.multiplierNonce,
  };
  const fingerprint = await cowQuoteFingerprint(material);
  const preview = { instrument: i, owner: request.from, receiver: request.from, inputAmountRaw: order.sellAmount,
    quotedOutputAmountRaw: buy, minimumOutputAmountRaw: order.buyAmount, estimatedNetworkFeeAmountRaw: fee,
    protocolFeeBps: Number(protocol), inputDecimals: input.side === "buy" ? 6 : state.tokenDecimals, outputDecimals,
    balanceRaw: input.side === "buy" ? state.usdcBalance : state.tokenBalance,
    allowanceRaw: input.side === "buy" ? state.usdcAllowance : state.tokenAllowance,
    stateBlock: state.block, multiplierRaw: state.multiplier, observedAt: new Date(state.at).toISOString(),
    expiresAt: new Date(Math.min(expiry, request.validTo * 1000)).toISOString(), providerVerified: r.verified,
    blockers: [...(BigInt(input.side === "buy" ? state.usdcBalance : state.tokenBalance) < BigInt(order.sellAmount) ? ["funding_required"] : []),
      ...(BigInt(input.side === "buy" ? state.usdcAllowance : state.tokenAllowance) < BigInt(order.sellAmount) ? ["approval_required"] : []),
      ...(!r.verified ? ["quote_unverified"] : []), "execution_disabled", "gas_sponsorship_unverified"],
    fingerprint, executable: false as const };
  return { preview, material };
}
export async function validateQuote(value: unknown, request: QuoteRequest, i: EVMInstrument,
  input: PreviewInput, state: ChainState, account: string, now: number) {
  return (await validateQuoteArtifacts(value, request, i, input, state, account, now)).preview;
}
