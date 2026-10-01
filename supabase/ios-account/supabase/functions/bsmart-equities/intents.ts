import { MarketError } from "../bsmart-markets/routing.ts";
import { address, atoms, previewInput, type PreviewInput } from "./quote.ts";
import type { previewEquity } from "./preview.ts";

export type EquityPreview = Awaited<ReturnType<typeof previewEquity>>;
export const INTENT_STATES = ["draft", "quoted", "authorized", "funding_pending", "funded", "order_pending", "filled",
  "return_pending", "completed", "expired", "rejected", "cancelled", "refund_pending", "needs_reconciliation"] as const;
export type IntentState = typeof INTENT_STATES[number];
export type IntentRow = {
  id: string; client_intent_id: string; account_id: string; wallet_address: string; request_hash: string;
  input: PreviewInput; state: IntentState; version: number; preview: EquityPreview | null;
  quote_expires_at: string | null; created_at: string; updated_at: string;
};
export type LegRow = { id: string; kind: "funding" | "approval" | "order" | "return";
  leg_index: number; source_network: "Ethereum" | "Ink" | "Arbitrum" | "HyperCore"; destination_network: "Ethereum" | "Ink" | "Arbitrum" | "HyperCore";
  state: "reserved" | "submitting" | "submitted" | "unknown" | "confirmed" | "failed";
  provider: "cow" | "across" | "relay" | "wallet"; provider_id: string; attempts: number; checked_at: string | null };
export type Ledger = {
  create: (account: string, owner: string, clientId: string, input: PreviewInput, hash: string) => Promise<IntentRow>;
  get: (account: string, id: string) => Promise<IntentRow>;
  legs: (account: string, id: string) => Promise<LegRow[]>;
  change: (account: string, id: string, owner: string, version: number, action: "quote" | "cancel", preview?: EquityPreview) => Promise<IntentRow>;
};
export function intentId(value: unknown): string {
  if (typeof value !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) throw new MarketError("invalid_intent", 422);
  return value.toLowerCase();
}
export function createInput(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new MarketError("invalid_intent", 422);
  const r = value as Record<string, unknown>;
  if (Object.keys(r).length !== 2 || !Object.hasOwn(r, "input") || !Object.hasOwn(r, "clientIntentId")) throw new MarketError("invalid_intent", 422);
  const input = previewInput(r.input);
  if (input.side === "buy" && BigInt(atoms(input.amount, 6)) > 100_000_000_000n) throw new MarketError("invalid_intent", 422);
  return { clientIntentId: intentId(r.clientIntentId), input };
}
export function expectedVersion(value: unknown): number {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new MarketError("invalid_intent", 422);
  const r = value as Record<string, unknown>;
  if (Object.keys(r).length !== 1 || !Number.isInteger(r.expectedVersion) || (r.expectedVersion as number) < 0 ||
    (r.expectedVersion as number) > 2147483646) throw new MarketError("invalid_intent", 422);
  return r.expectedVersion as number;
}
export async function requestHash(account: string, owner: string, input: PreviewInput) {
  // Fixed property order, including all user constraints, not client JSON key order.
  const canonical = { schema: 1, account: intentId(account), owner: address(owner), ticker: input.ticker, side: input.side,
    amount: input.amount, slippageBps: input.slippageBps, maxNetworkFeeBps: input.maxNetworkFeeBps, minimumOutput: input.minimumOutput ?? null };
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(canonical))))]
    .map(b => b.toString(16).padStart(2, "0")).join("");
}
export function refreshable(row: IntentRow, owner: string, version: number) {
  if (row.wallet_address !== address(owner)) throw new MarketError("wallet_changed", 409);
  if (row.version !== version) throw new MarketError("intent_version_conflict", 409);
  if (!["draft", "quoted"].includes(row.state)) throw new MarketError("intent_state_conflict", 409);
}
export function savedPreview(row: IntentRow, preview: EquityPreview, now: number): string {
  if (preview.ticker !== row.input.ticker || preview.side !== row.input.side || preview.executionEnabled !== false ||
    preview.returnTransferImplemented !== false || preview.gasCoverage !== "unverified" ||
    preview.defaultSaleProceedsDestination !== "hyperliquid_perps" || !preview.candidates.length || preview.candidates.length > 2) throw new MarketError("invalid_saved_preview");
  for (const c of preview.candidates) {
    if (c.owner !== row.wallet_address || c.receiver !== row.wallet_address || c.executable !== false ||
      !/^[0-9a-f]{64}$/.test(c.fingerprint) || !Number.isFinite(Date.parse(c.expiresAt)) ||
      Date.parse(c.expiresAt) <= now + 5000 || Date.parse(c.expiresAt) > now + 600_000 ||
      !Number.isFinite(Date.parse(c.observedAt)) || Date.parse(c.observedAt) > now || now - Date.parse(c.observedAt) >= 30_000) throw new MarketError("invalid_saved_preview");
  }
  return new Date(Math.min(...preview.candidates.map(c => Date.parse(c.expiresAt)))).toISOString();
}
export function intentResponse(row: IntentRow, legs: LegRow[] = []) {
  return { intent: { id: row.id, clientIntentId: row.client_intent_id, owner: row.wallet_address, input: row.input,
    state: row.state, version: row.version, preview: row.preview, quoteExpiresAt: row.quote_expires_at,
    createdAt: row.created_at, updatedAt: row.updated_at },
    legs: legs.map(l => ({ id: l.id, kind: l.kind, legIndex: l.leg_index, sourceNetwork: l.source_network,
      destinationNetwork: l.destination_network, state: l.state, provider: l.provider, providerId: l.provider_id,
      attempts: l.attempts, checkedAt: l.checked_at })), executionEnabled: false as const };
}

// Lease expiry changes recovery mode, never gives permission for a second submission.
export function recoveryAction(leg: Pick<LegRow, "state" | "attempts">, leaseUntil: number | null, now: number) {
  if (leg.state === "reserved" && leg.attempts === 0) return "claim";
  if (leg.state === "submitting" && leaseUntil !== null && now < leaseUntil) return "wait";
  if (["submitting", "submitted", "unknown"].includes(leg.state)) return "reconcile_only";
  return "terminal";
}
