import { readJSON } from "../bsmart-markets/providers.ts";
import { MarketError, object } from "../bsmart-markets/routing.ts";
import { address, atoms, raw } from "./quote.ts";
import { ceilMicro, floorMicro, FUNDING_CURRENCIES as currencies, HC_SPOT, type BridgeQuote, type BridgeRequest, type FundingSource } from "./funding_types.ts";

const invalid = () => new MarketError("bridge_quote_invalid");
export function relayFundingBody(request: BridgeRequest) {
  const from = currencies[request.source], to = currencies[request.destination];
  if (!from || !to || from.chainId === to.chainId || (from.chainId !== 1337 && to.chainId !== 1337)) throw invalid();
  const owner = address(request.owner);
  return { user: owner, recipient: owner, refundTo: owner, originChainId: from.chainId, destinationChainId: to.chainId,
    originCurrency: from.address, destinationCurrency: to.address, amount: raw(request.amountRaw, true), tradeType: "EXACT_INPUT",
    protocolVersion: "v2", useDepositAddress: false, usePermit: true, includeProtocolData: true,
    // Same-currency routes: do not silently consume the stock order's slippage budget.
    slippageTolerance: "0", ttl: 60, topupGas: false };
}
function currency(value: unknown, network: FundingSource) {
  const r = object(value), c = currencies[network];
  if (r.chainId !== c.chainId || typeof r.address !== "string" || r.address.toLowerCase() !== c.address || r.decimals !== c.decimals) throw invalid();
}
function deadline(value: unknown, now: number) {
  if (!Number.isSafeInteger(value) || (value as number) * 1000 <= now + 5000) throw new MarketError("bridge_quote_expired");
  return (value as number) * 1000;
}
function protocolCurrency(r: Record<string, unknown>, network: FundingSource) {
  const c = currencies[network];
  if (r.chainId !== c.protocolChain || typeof r.currency !== "string" || r.currency.toLowerCase() !== c.address) throw invalid();
}
export function validateRelayFunding(value: unknown, request: BridgeRequest, at: number, now: number): BridgeQuote {
  relayFundingBody(request);
  if (now < at || now - at >= 30_000) throw new MarketError("bridge_quote_expired");
  try {
    const r = object(value), d = object(r.details), input = object(d.currencyIn), output = object(d.currencyOut);
    const refund = object(d.refundCurrency), from = currencies[request.source], to = currencies[request.destination], owner = address(request.owner);
    if (d.operation !== "swap" || address(d.sender) !== owner || address(d.recipient) !== owner || raw(input.amount, true) !== request.amountRaw ||
      raw(input.minimumAmount, true) !== request.amountRaw) throw invalid();
    currency(input.currency, request.source); currency(output.currency, request.destination); currency(refund.currency, request.source);
    const expected = raw(output.amount, true), minimum = raw(output.minimumAmount, true);
    if (BigInt(expected) < BigInt(minimum)) throw invalid();
    const p = object(object(r.protocol).v2), order = object(p.orderData);
    if (!Array.isArray(order.inputs) || order.inputs.length !== 1 || !Array.isArray(order.fees) || order.fees.length) throw invalid();
    const i = object(order.inputs[0]), payment = object(i.payment), out = object(order.output), deposit = object(p.paymentDetails);
    protocolCurrency(payment, request.source);
    protocolCurrency(deposit, request.source);
    if (raw(deposit.amount, true) !== request.amountRaw) throw invalid();
    const depository = address(deposit.depository);
    if (raw(payment.amount, true) !== request.amountRaw || payment.weight !== "1" || out.chainId !== to.protocolChain ||
      !Array.isArray(out.calls) || out.calls.length || !Array.isArray(out.payments) || out.payments.length !== 1) throw invalid();
    const recipient = object(out.payments[0]);
    if (address(recipient.recipient) !== owner || String(recipient.currency).toLowerCase() !== to.address ||
      raw(recipient.minimumAmount, true) !== minimum || raw(recipient.expectedAmount, true) !== expected) throw invalid();
    let expires = Math.min(at + 30_000, deadline(out.deadline, now));
    if (!Array.isArray(i.refunds) || !i.refunds.length || i.refunds.length > 2) throw invalid();
    const refundNetworks: FundingSource[] = [];
    for (const value of i.refunds) {
      const rr = object(value);
      const network = ([request.source, request.destination] as FundingSource[]).find(n =>
        rr.chainId === currencies[n].protocolChain && typeof rr.currency === "string" && rr.currency.toLowerCase() === currencies[n].address);
      if (!network || refundNetworks.includes(network) || address(rr.recipient) !== owner) throw invalid();
      raw(rr.minimumAmount); deadline(rr.deadline, now); refundNetworks.push(network);
    }
    if (!refundNetworks.includes(request.source)) throw invalid();
    const gas = object(object(r.fees).gas), gasRaw = raw(gas.amount);
    if (!Array.isArray(r.steps) || !r.steps.length || r.steps.length > 3) throw invalid();
    const steps = r.steps.map(object), items = steps.map(s => {
      if (!Array.isArray(s.items) || s.items.length !== 1 || typeof s.requestId !== "string" || !/^0x[0-9a-f]{64}$/.test(s.requestId) ||
        !["signature", "transaction"].includes(s.kind as string)) throw invalid();
      const item = object(s.items[0]);
      if (item.status !== "incomplete") throw invalid();
      return object(item.data);
    });
    if (new Set(steps.map(s => s.requestId)).size !== 1) throw invalid();
    let mechanism: BridgeQuote["mechanism"], originNativeGasRequired = gasRaw !== "0";
    if (from.chainId === 1337) {
      if (steps.length !== 2 || steps[0].kind !== "signature" || steps[1].kind !== "transaction") throw invalid();
      const sign = object(items[0].sign), v = object(sign.value), action = object(items[1].action), params = object(action.parameters);
      if (sign.primaryType !== "NonceMapping" || sign.signatureKind !== "eip712" || v.chainId !== "hyperliquid" ||
        typeof v.id !== "string" || !/^0x[0-9a-f]{64}$/.test(v.id) || !Number.isSafeInteger(v.nonce) || (v.nonce as number) <= 0 ||
        address(v.wallet) !== owner || address(v.depositor) !== owner || address(params.destination) !== depository ||
        action.type !== "sendAsset" || params.hyperliquidChain !== "Mainnet" || params.fromSubAccount !== "" ||
        params.sourceDex !== (request.source === "HyperCoreSpot" ? "spot" : "") || params.destinationDex !== "" ||
        params.token !== "USDC:" + HC_SPOT || typeof params.amount !== "string" || atoms(params.amount, 8) !== request.amountRaw ||
        String(v.nonce) !== String(params.nonce) || String(items[1].nonce) !== String(params.nonce)) throw invalid();
      mechanism = "hypercore_nonce_mapping";
    } else if (steps.length === 1 && steps[0].kind === "signature") {
      const sign = object(items[0].sign), v = object(sign.value);
      const domain = object(sign.domain);
      // Permit's recipient can be Relay's execution router, not the depository.
      // Validate shape here only; P5 must authenticate/allowlist that executor before signing.
      address(v.to);
      if (sign.primaryType !== "ReceiveWithAuthorization" || sign.signatureKind !== "eip712" ||
        domain.chainId !== from.chainId || address(domain.verifyingContract) !== from.address ||
        address(v.from) !== owner || raw(String(v.value), true) !== request.amountRaw) throw invalid();
      expires = Math.min(expires, deadline(Number(v.validBefore), now));
      mechanism = "permit_candidate";
    } else {
      mechanism = "evm_transaction"; originNativeGasRequired = true;
    }
    if (expires <= now + 5000) throw new MarketError("bridge_quote_expired");
    const loss = ceilMicro(BigInt(request.amountRaw), from.decimals) - floorMicro(BigInt(minimum), to.decimals);
    return { provider: "relay", source: request.source, destination: request.destination, inputAmountRaw: request.amountRaw,
      inputDecimals: from.decimals, expectedOutputAmountRaw: expected, minimumOutputAmountRaw: minimum, outputDecimals: to.decimals,
      maximumLossUsdcRaw: String(loss > 0n ? loss : 0n), originNativeGasRequired, mechanism, refundNetworks,
      observedAt: new Date(at).toISOString(), expiresAt: new Date(expires).toISOString() };
  } catch (error) {
    throw error instanceof MarketError && error.code.startsWith("bridge_") ? error : invalid();
  }
}
export function relayFundingQuote(key?: string, fetcher: typeof fetch = fetch, now: () => number = Date.now) {
  return async (request: BridgeRequest): Promise<BridgeQuote> => {
    const body = relayFundingBody(request), at = now();
    let response: unknown;
    try { response = await readJSON("https://api.relay.link/quote/v2", { method: "POST",
      headers: { "Content-Type": "application/json", ...(key ? { "x-api-key": key } : {}) }, body: JSON.stringify(body) }, fetcher); }
    catch { throw new MarketError("bridge_quote_unavailable"); }
    return validateRelayFunding(response, request, at, now());
  };
}
