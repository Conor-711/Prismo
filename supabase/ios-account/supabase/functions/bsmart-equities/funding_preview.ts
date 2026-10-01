import { MarketError } from "../bsmart-markets/routing.ts";
import { type IntentRow, refreshable, savedPreview } from "./intents.ts";
import { address, atoms, raw, validateState } from "./quote.ts";
import { resolveEVMRoute, resolveExitInstruments, type EVMCatalogs } from "./routing.ts";
import { ceilMicro, floorMicro, type BridgeQuote, type BridgeRequest, type FundingPlan, type FundingPorts } from "./funding_types.ts";

export function fundingIntent(row: IntentRow, owner: string, version: number, now: number) {
  refreshable(row, owner, version);
  if (row.state !== "quoted" || !row.preview || !row.quote_expires_at || !Number.isFinite(Date.parse(row.quote_expires_at)) ||
    Date.parse(row.quote_expires_at) <= now + 5000) throw new MarketError("funding_preview_expired", 409);
  try { savedPreview(row, row.preview, now); } catch { throw new MarketError("funding_preview_expired", 409); }
}
function bridgeBound(q: BridgeQuote, request: BridgeRequest, now: number) {
  if (q.provider !== "relay" || q.source !== request.source || q.destination !== request.destination ||
    q.inputAmountRaw !== request.amountRaw || q.inputDecimals !== (request.source.startsWith("HyperCore") ? 8 : 6) ||
    q.outputDecimals !== (request.destination === "HyperCorePerps" ? 8 : 6) ||
    Date.parse(q.expiresAt) <= now + 5000 || !Number.isFinite(Date.parse(q.expiresAt)) ||
    !Number.isFinite(Date.parse(q.observedAt)) || Date.parse(q.observedAt) > now || now - Date.parse(q.observedAt) >= 30_000) throw new MarketError("bridge_quote_invalid");
  const min = BigInt(raw(q.minimumOutputAmountRaw, true)), max = BigInt(raw(q.expectedOutputAmountRaw, true));
  const loss = ceilMicro(BigInt(raw(q.inputAmountRaw, true)), q.inputDecimals) - floorMicro(min, q.outputDecimals);
  if (min > max || BigInt(raw(q.maximumLossUsdcRaw)) !== (loss > 0n ? loss : 0n)) throw new MarketError("bridge_quote_invalid");
  if (q.originNativeGasRequired) throw new MarketError("bridge_native_gas_required", 409);
}
export async function fundingPreview(row: IntentRow, boundOwner: string, catalogs: EVMCatalogs, ports: FundingPorts, now: () => number = Date.now) {
  const owner = address(boundOwner); fundingIntent(row, owner, row.version, now());
  await ports.assertIdle(row.account_id, owner, row.id);
  const selected = async () => {
    if (row.input.side === "sell") return (await resolveExitInstruments(row.input.ticker, catalogs, now)).instruments;
    const route = await resolveEVMRoute(row.input.ticker, catalogs, now);
    if (route.venue !== "xstocks" || route.status !== "available") throw new MarketError("xstocks_route_required", 409);
    return route.instruments;
  };
  const instruments = await selected(), plans: FundingPlan[] = [], failures: { network: "Ethereum" | "Ink"; error: string }[] = [];
  const candidates = row.preview!.candidates;
  for (const c of candidates) {
    const i = c.instrument;
    try {
      if (!instruments.some(x => JSON.stringify(x) === JSON.stringify(i))) throw new MarketError("instrument_changed", 409);
      const state = await ports.state(i, owner); validateState(state, i, owner, now());
      if (state.multiplier !== c.multiplierRaw || BigInt(state.block) < BigInt(c.stateBlock)) throw new MarketError("corporate_action_changed");
      const budget = row.input.side === "buy" ? BigInt(atoms(row.input.amount, 6)) : BigInt(raw(c.minimumOutputAmountRaw, true));
      if (row.input.side === "buy" && (c.inputAmountRaw !== String(budget) || c.inputDecimals !== 6) ||
        row.input.side === "sell" && (c.outputDecimals !== 6 || BigInt(raw(c.inputAmountRaw, true)) > BigInt(state.tokenBalance))) throw new MarketError("funding_order_mismatch");
      const cowCost = row.input.side === "buy" ? BigInt(raw(c.estimatedNetworkFeeAmountRaw)) : 0n;
      const cap = budget * BigInt(row.input.maxNetworkFeeBps) / 10_000n;
      if (cowCost > cap) throw new MarketError("funding_fee_limit", 409);
      const usdc = BigInt(state.usdcBalance), deficit = row.input.side === "buy" && budget > usdc ? budget - usdc : 0n;
      let bridge: BridgeQuote | null = null, source: FundingPlan["source"] = "execution_chain";
      let hcInput = 0n, hcSource: string | null = null, hcMode: string | null = null;
      if (row.input.side === "sell" || deficit > 0n) {
        let request: BridgeRequest;
        if (row.input.side === "sell") {
          source = "sale_proceeds";
          request = { owner, source: i.network, destination: "HyperCorePerps", amountRaw: String(budget) };
        } else {
          source = "hyperliquid";
          const hc = await ports.hypercore(owner);
          if (!["HyperCoreSpot", "HyperCorePerps"].includes(hc.source) || hc.owner !== owner || !Number.isFinite(hc.at) || hc.at > now() || now() - hc.at >= 30_000 ||
            hc.source === "HyperCoreSpot" && (!hc.flatAccountChecked || hc.mode !== "unifiedAccount") ||
            hc.source === "HyperCorePerps" && !["default", "disabled", "dexAbstraction"].includes(hc.mode)) throw new MarketError("hypercore_funds_unavailable");
          const available = BigInt(raw(hc.availableRaw)), maximum = (deficit + cap - cowCost) * 100n;
          hcInput = available < maximum ? available : maximum; hcSource = hc.source; hcMode = hc.mode;
          if (hcInput < deficit * 100n) throw new MarketError("funding_insufficient_balance", 409);
          request = { owner, source: hc.source, destination: i.network, amountRaw: String(hcInput) };
        }
        bridge = await ports.bridge(request); bridgeBound(bridge, request, now());
        if (deficit > 0n && BigInt(bridge.minimumOutputAmountRaw) < deficit) throw new MarketError("funding_insufficient_output", 409);
        if (cowCost + BigInt(bridge.maximumLossUsdcRaw) > cap) throw new MarketError("funding_fee_limit", 409);
      }
      const latest = await ports.state(i, owner); validateState(latest, i, owner, now());
      if (latest.usdcBalance !== state.usdcBalance || latest.tokenBalance !== state.tokenBalance ||
        latest.multiplier !== state.multiplier || latest.multiplierNonce !== state.multiplierNonce ||
        BigInt(latest.block) < BigInt(state.block)) throw new MarketError("funding_balance_changed", 409);
      if (hcInput) {
        const hc = await ports.hypercore(owner);
        if (hc.owner !== owner || hc.source !== hcSource || hc.mode !== hcMode || !Number.isFinite(hc.at) || hc.at > now() || now() - hc.at >= 30_000 || BigInt(raw(hc.availableRaw)) < hcInput ||
          hc.source === "HyperCoreSpot" && (!hc.flatAccountChecked || hc.mode !== "unifiedAccount")) throw new MarketError("hypercore_funds_changed", 409);
      }
      const expires = Math.min(Date.parse(c.expiresAt), Date.parse(bridge?.expiresAt ?? c.expiresAt), state.at + 30_000);
      if (expires <= now() + 5000) throw new MarketError("funding_preview_expired", 409);
      plans.push({ instrument: i, orderFingerprint: c.fingerprint, executionChainUsdcRaw: state.usdcBalance,
        deficitUsdcRaw: String(deficit), source, saleProceedsBasis: row.input.side === "sell" ? "quoted_minimum" : null,
        bridge, costBoundUsdcRaw: String(cowCost + BigInt(bridge?.maximumLossUsdcRaw ?? "0")),
        costScope: row.input.side === "buy" ? "buy_cow_network_and_bridge" : "sell_bridge_only", expiresAt: new Date(expires).toISOString(),
        blockers: [...new Set([...c.blockers.filter(b => b !== "funding_required"),
          ...(BigInt(row.input.side === "buy" ? latest.usdcAllowance : latest.tokenAllowance) < BigInt(c.inputAmountRaw) ? ["approval_required"] : []),
          ...(deficit > 0n ? ["funding_authorization_required"] : []),
          ...(row.input.side === "sell" ? ["sale_fill_required", "fresh_return_quote_required"] : []),
          ...(bridge?.mechanism === "permit_candidate" ? ["permit_executor_unverified"] : []),
          "wallet_reservation_required", "signing_validation_required", "execution_disabled", "gas_sponsorship_unverified"])] });
    } catch (error) { failures.push({ network: i.network, error: error instanceof MarketError ? error.code : "funding_preview_unavailable" }); }
  }
  if (JSON.stringify(await selected()) !== JSON.stringify(instruments)) throw new MarketError("instrument_changed", 409);
  await ports.assertIdle(row.account_id, owner, row.id); fundingIntent(row, owner, row.version, now());
  for (const p of plans.filter(p => Date.parse(p.expiresAt) <= now() + 5000)) failures.push({ network: p.instrument.network, error: "funding_preview_expired" });
  return { intentId: row.id, version: row.version, owner, side: row.input.side,
    plans: plans.filter(p => Date.parse(p.expiresAt) > now() + 5000), failures, observedAt: new Date(now()).toISOString(),
    executionEnabled: false as const, gasCoverage: "unverified" as const, reservationsImplemented: false as const, returnTransferImplemented: false as const };
}
