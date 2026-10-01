import { MarketError } from "../bsmart-markets/routing.ts";
import { prepareCowOrder, assertPreparedCowOrder, verifyBoundCowSignature, type PreparedCowOrder } from "./cow_order.ts";
import { refreshable, savedPreview, type EquityPreview, type IntentRow } from "./intents.ts";
import { address, type CowQuoteMaterial } from "./quote.ts";
import { previewEquityArtifacts, type PreviewPorts } from "./preview.ts";
import { resolveEVMRoute, resolveExitInstruments, type EVMCatalogs } from "./routing.ts";

export type PreparationRow = {
  intent_id: string; account_id: string; wallet_address: string; intent_version: number;
  network: "Ethereum" | "Ink"; order_uid: string; fingerprint: string; preparation_hash: string;
  material: CowQuoteMaterial; prepared: PreparedCowOrder; expires_at: string;
  state: "reserved" | "signing" | "authorized" | "released"; signature: string | null;
  signing_started_at?: string | null;
  authorization_hash: string | null; authorized_at: string | null; created_at: string;
};
export type PreparationLedger = {
  get: (account: string, id: string) => Promise<PreparationRow | null>;
  reserve: (row: IntentRow, owner: string, version: number, preview: EquityPreview,
    material: CowQuoteMaterial, prepared: PreparedCowOrder, hash: string) => Promise<PreparationRow>;
  authorize: (row: PreparationRow, signature: string, hash: string) => Promise<PreparationRow>;
  startSigning: (row: PreparationRow) => Promise<PreparationRow>;
};
export type PreparationPorts = {
  ledger: PreparationLedger; getIntent: (account: string, id: string) => Promise<IntentRow>;
  boundOwner: () => Promise<string>; assertIdle: (account: string, owner: string, id: string) => Promise<void>;
  catalogs: EVMCatalogs; preview: PreviewPorts; now?: () => number;
};
const conflict = () => new MarketError("preparation_conflict", 409);

// Stable under jsonb key reordering. These private objects are validated before hashing.
function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)
    .map(([key, child]) => [key, canonical(child)]));
  return value;
}
async function digest(value: unknown) {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify(canonical(value)))))]
    .map(b => b.toString(16).padStart(2, "0")).join("");
}
export const preparationHash = (material: CowQuoteMaterial, prepared: PreparedCowOrder) => digest({ schema: "equity_preparation_v1", material, prepared });

export async function assertStoredPreparation(p: PreparationRow, account: string, id: string) {
  if (p.account_id !== account || p.intent_id !== id) throw new MarketError("intent_not_found", 404);
  await assertPreparedCowOrder(p.prepared);
  if (p.prepared.account !== account || p.prepared.intentId !== id || p.prepared.owner !== p.wallet_address ||
    p.material.owner !== p.wallet_address || p.material.account !== account || p.intent_version !== p.prepared.intentVersion ||
    p.order_uid !== p.prepared.orderUid || p.fingerprint !== p.prepared.fingerprint || p.network !== p.prepared.instrument.network ||
    Date.parse(p.expires_at) !== Date.parse(p.prepared.expiresAt) || p.preparation_hash !== await preparationHash(p.material, p.prepared)) throw conflict();
}
export function preparationResponse(p: PreparationRow) {
  if (p.state !== "reserved") throw conflict();
  return { intentId: p.intent_id, version: p.intent_version, owner: p.wallet_address, fingerprint: p.fingerprint,
    orderUid: p.order_uid, network: p.network, expiresAt: p.prepared.expiresAt, state: "reserved" as const,
    reservationsImplemented: true as const, signingEnabled: false as const, executionEnabled: false as const };
}
export async function assertPreparationMarket(p: PreparedCowOrder, row: IntentRow, catalogs: EVMCatalogs, now: () => number) {
  const instruments = row.input.side === "sell" ? (await resolveExitInstruments(row.input.ticker, catalogs, now)).instruments :
    await (async () => {
      const route = await resolveEVMRoute(row.input.ticker, catalogs, now);
      if (route.venue !== "xstocks" || route.status !== "available") throw new MarketError("xstocks_route_required", 409);
      return route.instruments;
    })();
  if (!instruments.some(i => Object.keys(i).every(k => i[k as keyof typeof i] === p.instrument[k as keyof typeof i]))) {
    throw new MarketError("instrument_changed", 409);
  }
}
function boundIntent(row: IntentRow, account: string, id: string) {
  if (row.account_id !== account || row.id !== id) throw new MarketError("intent_not_found", 404);
}

export async function prepareIntent(row: IntentRow, version: number, ports: PreparationPorts) {
  const now = ports.now ?? Date.now, owner = address(await ports.boundOwner());
  const existing = await ports.ledger.get(row.account_id, row.id);
  if (existing) {
    await assertStoredPreparation(existing, row.account_id, row.id);
    if (existing.state !== "reserved" || row.state !== "quoted" || row.version !== existing.intent_version) throw conflict();
    if (![existing.intent_version, existing.intent_version - 1].includes(version)) throw new MarketError("intent_version_conflict", 409);
    if (owner !== existing.wallet_address) throw new MarketError("wallet_changed", 409);
    // Same RPC rechecks CAS, expiry, wallet and activity after a lost response.
    return preparationResponse(await ports.ledger.reserve(row, owner, version, row.preview!, existing.material,
      existing.prepared, existing.preparation_hash));
  }
  refreshable(row, owner, version);
  if (version > 2147483644) throw new MarketError("intent_version_conflict", 409);
  await ports.assertIdle(row.account_id, owner, row.id);
  const { preview, materials } = await previewEquityArtifacts(row.input, row.account_id, owner, ports.catalogs, ports.preview, now);
  const quoted: IntentRow = { ...row, state: "quoted", version: version + 1, preview, quote_expires_at: savedPreview(row, preview, now()) };
  const candidates: { material: CowQuoteMaterial; prepared: PreparedCowOrder; decimals: number }[] = [];
  for (const material of materials) {
    try {
      const state = await ports.preview.state(material.instrument, owner);
      const prepared = await prepareCowOrder(material, quoted, quoted.version, state, now(), await ports.boundOwner());
      candidates.push({ material, prepared, decimals: row.input.side === "buy" ? state.tokenDecimals : 6 });
    } catch (error) {
      if (!(error instanceof MarketError) || !["quote_unverified", "funding_required", "approval_required"].includes(error.code)) throw error;
    }
  }
  if (!candidates.length) throw new MarketError("funded_approved_quote_required", 409);
  candidates.sort((a, b) => {
    const left = BigInt(a.prepared.order.buyAmount) * 10n ** BigInt(b.decimals);
    const right = BigInt(b.prepared.order.buyAmount) * 10n ** BigInt(a.decimals);
    return left === right ? a.prepared.instrument.network.localeCompare(b.prepared.instrument.network) : left > right ? -1 : 1;
  });
  const { material, prepared } = candidates[0];
  // The reservation binds one chain/order. Do not let an unselected candidate's
  // shorter expiration invalidate it, or persist alternatives as authorizations.
  const selectedPreview = { ...preview, candidates: preview.candidates.filter(c => c.fingerprint === prepared.fingerprint) };
  await assertPreparationMarket(prepared, row, ports.catalogs, now);
  const latest = await ports.getIntent(row.account_id, row.id);
  boundIntent(latest, row.account_id, row.id); refreshable(latest, await ports.boundOwner(), version);
  // RPC persists quote, immutable raw material and reservation in one transaction.
  const stored = await ports.ledger.reserve(row, owner, version, selectedPreview, material, prepared, await preparationHash(material, prepared));
  await assertStoredPreparation(stored, row.account_id, row.id);
  return preparationResponse(stored);
}

// Internal-only orchestration. No current HTTP path exposes typed data or accepts
// signatures. Sells are blocked until bounded return consent is implemented.
export async function authorizePreparedIntent(account: string, id: string, version: number, signature: unknown, ports: PreparationPorts) {
  const now = ports.now ?? Date.now, p = await ports.ledger.get(account, id);
  if (!p) throw conflict();
  await assertStoredPreparation(p, account, id);
  if (p.prepared.side !== "buy") throw new MarketError("return_authorization_unavailable", 409);
  if (p.intent_version !== version || typeof signature !== "string" || !/^0x[0-9a-fA-F]{130}$/.test(signature)) throw conflict();
  const normalized = signature.toLowerCase();
  const authorizationHash = await digest({ schema: "equity_authorization_v1", preparationHash: p.preparation_hash, signature: normalized });
  if (p.state === "authorized") {
    if (p.signature !== normalized || p.authorization_hash !== authorizationHash || address(await ports.boundOwner()) !== p.wallet_address) throw conflict();
    // This is a read/identical CAS replay of accepted consent, even after expiry;
    // it creates no new permission and never refreshes an order or releases funds.
    return await ports.ledger.authorize(p, normalized, authorizationHash);
  }
  if (p.state !== "signing" || !p.signing_started_at) throw conflict();
  const row = await ports.getIntent(account, id); boundIntent(row, account, id);
  await ports.assertIdle(account, p.wallet_address, id);
  await assertPreparationMarket(p.prepared, row, ports.catalogs, now);
  const state = await ports.preview.state(p.prepared.instrument, p.wallet_address);
  await verifyBoundCowSignature(p.prepared, p.material, row, version, state, signature, now(), await ports.boundOwner());
  // Providers can take time: repeat market and owner checks before atomic authorization.
  await assertPreparationMarket(p.prepared, row, ports.catalogs, now);
  if (address(await ports.boundOwner()) !== p.wallet_address) throw new MarketError("wallet_changed", 409);
  return await ports.ledger.authorize(p, normalized, authorizationHash);
}
