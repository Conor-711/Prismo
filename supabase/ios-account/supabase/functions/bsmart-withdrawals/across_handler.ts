import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { verifyTypedData } from "npm:viem@2.56.3";

const ORIGIN = 1337;
const DESTINATION = 42161;
const USDC_SPOT = "0x2000000000000000000000000000000000000000";
const USDC_PERPS = "0x2100000000000000000000000000000000000000";
const ARBITRUM_USDC = "0xaf88d065e77c8cc2239327c5edb3a432268e5831";
const API = "https://app.across.to/api";
const active = ["quoted", "submitting", "submitted", "uncertain", "deposit_pending", "expired"];

type Row = {
  id: string;
  account_id: string;
  wallet_address: string;
  recipient: string;
  source_dex: string;
  amount_units: string;
  quote: Record<string, unknown>;
  quote_expires_at: string;
  deposit_id: string;
  state: string;
  provider_status: string | null;
  created_at: string;
  checked_at: string | null;
};
type Step = {
  stepId: string;
  ecosystem: "hypercore" | "evm-gasless";
  typedData: Record<string, unknown>;
};
export type AcrossPorts = {
  quote: (params: URLSearchParams) => Promise<unknown>;
  submit: (body: unknown) => Promise<unknown>;
  status: (depositId: string) => Promise<unknown>;
};

export class AcrossProviderError extends Error {
  constructor(readonly status: number, readonly code: string | null) {
    super("provider_unavailable");
  }
}

const reply = (value: unknown, status = 200) =>
  Response.json(value, { status, headers: { "Cache-Control": "no-store" } });
const record = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value);
const address = (value: unknown): value is string =>
  typeof value === "string" && /^0x[0-9a-f]{40}$/.test(value) &&
  value !== "0x0000000000000000000000000000000000000000";
const uuid = (value: unknown): value is string =>
  typeof value === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value);
const digits = (value: unknown): value is string =>
  typeof value === "string" && /^[0-9]{1,100}$/.test(value);

export function usdcUnits(value: unknown): string | null {
  if (typeof value !== "string" || !/^(0|[1-9][0-9]{0,11})(\.[0-9]{1,6})?$/.test(value)) return null;
  const [whole, fraction = ""] = value.split(".");
  const units = BigInt(whole) * 100_000_000n + BigInt(fraction.padEnd(8, "0"));
  return units > 0n ? String(units) : null;
}

function steps(quote: Record<string, unknown>): Step[] | null {
  if (!Array.isArray(quote.swapTxns) || quote.swapTxns.length !== 2) return null;
  const result: Step[] = [];
  for (const raw of quote.swapTxns) {
    if (!record(raw) || typeof raw.stepId !== "string" || !/^[a-zA-Z0-9_-]{1,80}$/.test(raw.stepId) ||
        !["hypercore", "evm-gasless"].includes(String(raw.ecosystem)) || !record(raw.typedData)) return null;
    const typed = raw.typedData;
    if (!record(typed.domain) || !record(typed.types) || !record(typed.message) ||
        typeof typed.primaryType !== "string" || !/^[A-Za-z0-9_:]{1,120}$/.test(typed.primaryType)) return null;
    if (raw.ecosystem === "evm-gasless" && Number(typed.domain.chainId) !== 999) return null;
    result.push(raw as Step);
  }
  return new Set(result.map((step) => step.stepId)).size === 2 &&
      new Set(result.map((step) => step.ecosystem)).size === 2 ? result : null;
}

export function validQuote(value: unknown, source: "spot" | "perps", units: string, now = Date.now()):
  value is Record<string, unknown> {
  if (!record(value) || !record(value.inputToken) || !record(value.outputToken) ||
      !record(value.refundToken) || !record(value.fees) || !record(value.fees.submission) ||
      !digits(value.fees.submission.amount) || !record(value.fees.submission.token) ||
      value.swapTx !== null || !steps(value) ||
      !digits(value.depositId) || value.inputAmount !== units ||
      value.inputToken.chainId !== ORIGIN ||
      String(value.inputToken.address).toLowerCase() !== (source === "spot" ? USDC_SPOT : USDC_PERPS) ||
      value.inputToken.decimals !== 8 || value.outputToken.chainId !== DESTINATION ||
      String(value.outputToken.address).toLowerCase() !== ARBITRUM_USDC ||
      value.outputToken.decimals !== 6 || value.refundToken.chainId !== 999 ||
      !digits(value.expectedOutputAmount) || !digits(value.minOutputAmount) ||
      BigInt(value.minOutputAmount) === 0n ||
      BigInt(value.expectedOutputAmount) < BigInt(value.minOutputAmount) ||
      !Number.isSafeInteger(value.quoteExpiryTimestamp) ||
      Number(value.quoteExpiryTimestamp) * 1000 <= now + 5_000 ||
      Number(value.quoteExpiryTimestamp) * 1000 > now + 300_000) return false;
  return true;
}

export async function reconcileAcross(req: Request, client: SupabaseClient, ports: AcrossPorts): Promise<Response> {
  if (req.method !== "POST" || !new URL(req.url).pathname.endsWith("/bsmart-withdrawals/reconcile")) {
    return reply({ error: "not_found" }, 404);
  }
  const token = req.headers.get("authorization")?.replace(/^Bearer /, "") ?? "";
  if (!/^[0-9a-f]{64}$/.test(token)) return reply({ error: "unauthorized" }, 401);
  const { data: authorized, error: authError } = await client.rpc("bsmart_across_worker_authorized", { p_token: token });
  if (authError || authorized !== true) return reply({ error: "unauthorized" }, 401);
  const { data, error } = await client.from("bsmart_across_withdrawals").select("*")
    .in("state", ["submitting", "submitted", "uncertain", "deposit_pending", "expired"])
    .order("checked_at", { ascending: true, nullsFirst: true }).limit(15);
  if (error) return reply({ error: "withdrawal_unavailable" }, 503);
  const rows = await Promise.all((data as Row[]).map(async (row) => {
    try { return await refresh(client, row, ports); }
    catch { return row; }
  }));
  return reply({ checked: rows.length });
}

async function json(req: Request, limit = 4096): Promise<unknown> {
  if (!req.headers.get("content-type")?.startsWith("application/json")) throw new Error("invalid_input");
  const bytes = new Uint8Array(await req.arrayBuffer());
  if (!bytes.length || bytes.length > limit) throw new Error("invalid_input");
  return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
}

async function providerJSON(response: Response): Promise<unknown> {
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.length > 131072) throw new Error("provider_unavailable");
  const value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  if (!response.ok) {
    const code = record(value) && typeof value.code === "string" && /^[A-Z_]{1,64}$/.test(value.code)
      ? value.code : null;
    throw new AcrossProviderError(response.status, code);
  }
  return value;
}

async function providerFetch(path: string, key: string, init?: RequestInit): Promise<unknown> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 12000);
  try {
    return await providerJSON(await fetch(`${API}${path}`, {
      ...init,
      headers: { "Authorization": `Bearer ${key}`, "Content-Type": "application/json" },
      signal: controller.signal,
    }));
  } finally { clearTimeout(timer); }
}

export function livePorts(key: string): AcrossPorts {
  return {
    quote: (params) => providerFetch(`/swap/gasless?${params}`, key),
    submit: (body) => providerFetch("/gasless/submit", key, { method: "POST", body: JSON.stringify(body) }),
    status: (depositId) => providerFetch(`/deposit/status?depositId=${encodeURIComponent(depositId)}&originChainId=1337`, key),
  };
}

function publicRow(row: Row) {
  const quote = row.quote;
  const fee = record(quote.fees) && record(quote.fees.submission) ? quote.fees.submission : null;
  const feeToken = fee && record(fee.token) ? fee.token : null;
  return {
    id: row.id, walletAddress: row.wallet_address, recipient: row.recipient,
    sourceDex: row.source_dex, amountUnits: String(row.amount_units),
    expectedOutputUnits: quote.expectedOutputAmount, minOutputUnits: quote.minOutputAmount,
    submissionFeeUnits: fee && digits(fee.amount) ? fee.amount : null,
    submissionFeeDecimals: feeToken && Number.isInteger(feeToken.decimals) ? feeToken.decimals : null,
    submissionFeeSymbol: feeToken && typeof feeToken.symbol === "string" ? feeToken.symbol : null,
    quoteExpiresAt: row.quote_expires_at, depositId: row.deposit_id,
    state: row.state, providerStatus: row.provider_status, createdAt: row.created_at,
  };
}

async function change(client: SupabaseClient, row: Row, from: string, to: string, extra: Record<string, unknown> = {}): Promise<Row> {
  const { data, error } = await client.from("bsmart_across_withdrawals")
    .update({ state: to, updated_at: new Date().toISOString(), ...extra })
    .eq("id", row.id).eq("account_id", row.account_id).eq("state", from).select("*").maybeSingle();
  if (error || !data) throw new Error("state_conflict");
  return data as Row;
}

async function signedSteps(quote: Record<string, unknown>, signatures: unknown, owner: string): Promise<boolean> {
  const required = steps(quote);
  if (!required || !record(signatures) || Object.keys(signatures).length !== required.length) return false;
  for (const step of required) {
    const signature = signatures[step.stepId];
    if (typeof signature !== "string" || !/^0x[0-9a-fA-F]{130}$/.test(signature)) return false;
    try {
      const typed = step.typedData;
      const valid = await verifyTypedData({
        address: owner as `0x${string}`,
        domain: typed.domain,
        types: typed.types,
        primaryType: typed.primaryType,
        message: typed.message,
        signature: signature as `0x${string}`,
      } as Parameters<typeof verifyTypedData>[0]);
      if (!valid) return false;
    } catch { return false; }
  }
  return true;
}

async function refresh(client: SupabaseClient, row: Row, ports: AcrossPorts): Promise<Row> {
  if (row.state === "quoted" && Date.parse(row.quote_expires_at) <= Date.now()) {
    return await change(client, row, "quoted", "quote_expired");
  }
  if (!["submitting", "submitted", "uncertain", "deposit_pending", "expired"].includes(row.state) ||
      row.checked_at && Date.now() - Date.parse(row.checked_at) < 10_000) return row;
  try {
    const result = await ports.status(row.deposit_id);
    if (!record(result) || typeof result.status !== "string") return row;
    const states: Record<string, string> = {
      pending: "deposit_pending", "deposit-pending": "deposit_pending", received: "deposit_pending",
      filled: "filled", "deposit-failed": "deposit_failed", expired: "expired", refunded: "refunded",
    };
    const next = states[result.status];
    if (!next || (row.state === "expired" && next === "deposit_pending")) return row;
    return await change(client, row, row.state, next, {
      provider_status: result.status, checked_at: new Date().toISOString(),
    });
  } catch { return row; }
}

export async function handleAcross(req: Request, client: SupabaseClient, enabled: boolean,
  key: string | undefined, integratorId: string | undefined, ports?: AcrossPorts): Promise<Response> {
  const path = new URL(req.url).pathname.split("/bsmart-withdrawals")[1] ?? "/";
  const submitMatch = /^\/([0-9a-f-]{36})\/submit$/.exec(path);
  const cancelMatch = /^\/([0-9a-f-]{36})\/cancel$/.exec(path);
  if (!(path === "" && req.method === "GET") && !(path === "/quote" && req.method === "POST") &&
      !(submitMatch && req.method === "POST") && !(cancelMatch && req.method === "POST")) {
    return reply({ error: "upgrade_required" }, 426);
  }
  const bearer = req.headers.get("authorization") ?? "";
  if (!/^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(bearer) || bearer.length > 16400) {
    return reply({ error: "unauthorized" }, 401);
  }
  try {
    const { data: { user }, error } = await client.auth.getUser(bearer.slice(7));
    if (error || !user || user.is_anonymous || !user.identities?.some((i) => ["apple", "google"].includes(i.provider))) {
      return reply({ error: "unauthorized" }, 401);
    }
    const { data: wallet, error: walletError } = await client.from("bsmart_wallets")
      .select("address").eq("account_id", user.id).maybeSingle();
    if (walletError || !address(wallet?.address)) return reply({ error: "wallet_unavailable" }, 503);
    const owner = wallet.address;
    const provider = ports ?? (key ? livePorts(key) : null);
    if (path === "" && req.method === "GET") {
      const { data, error: listError } = await client.from("bsmart_across_withdrawals")
        .select("*").eq("account_id", user.id).order("created_at", { ascending: false }).limit(30);
      if (listError) throw listError;
      const rows: Row[] = [];
      for (const item of data as Row[]) {
        if (item.wallet_address !== owner) continue;
        rows.push(provider ? await refresh(client, item, provider) : item);
      }
      return reply({ withdrawals: rows.map(publicRow) });
    }
    if (!enabled || !provider || !integratorId || !/^0x[0-9a-fA-F]{4}$/.test(integratorId)) {
      return reply({ error: "withdrawals_disabled" }, 503);
    }
    if (path === "/quote") {
      const input = await json(req);
      if (!record(input) || Object.keys(input).sort().join() !== ["amount", "id", "recipient", "sourceDex", "walletAddress"].sort().join() ||
          !uuid(input.id) || input.walletAddress !== owner || !address(input.recipient) ||
          !["spot", "perps"].includes(String(input.sourceDex))) return reply({ error: "invalid_input" }, 422);
      const units = usdcUnits(input.amount);
      if (!units) return reply({ error: "invalid_input" }, 422);
      const { data: oldPending, error: oldError } = await client.from("bsmart_withdrawals")
        .select("id").eq("wallet_address", owner).in("state", ["reserved", "submitting", "accepted", "uncertain", "core_debited"]).limit(1);
      if (oldError) throw oldError;
      if (oldPending?.length) return reply({ error: "withdrawal_pending" }, 409);
      const params = new URLSearchParams({
        inputToken: input.sourceDex === "spot" ? USDC_SPOT : USDC_PERPS,
        originChainId: String(ORIGIN), outputToken: ARBITRUM_USDC,
        destinationChainId: String(DESTINATION), amount: units,
        depositor: owner, recipient: input.recipient, integratorId,
        tradeType: "exactInput", refundOnOrigin: "true", refundAddress: owner,
      });
      let quote: unknown;
      try { quote = await provider.quote(params); }
      catch (error) {
        if (error instanceof AcrossProviderError) {
          console.warn("Across quote rejected", error.status, error.code);
          if ([401, 403].includes(error.status)) return reply({ error: "provider_not_authorized" }, 503);
          if ([400, 422].includes(error.status)) return reply({ error: "quote_unavailable" }, 422);
        }
        return reply({ error: "provider_unavailable" }, 503);
      }
      if (!validQuote(quote, input.sourceDex as "spot" | "perps", units)) return reply({ error: "provider_unavailable" }, 503);
      const { data, error: reserveError } = await client.rpc("bsmart_across_withdrawal_reserve", {
        p_account: user.id, p_id: input.id, p_wallet: owner, p_recipient: input.recipient,
        p_source: input.sourceDex, p_amount_units: units, p_quote: quote,
        p_quote_expires_at: new Date(Number(quote.quoteExpiryTimestamp) * 1000).toISOString(),
        p_deposit_id: quote.depositId,
      });
      if (reserveError) return reply({ error: reserveError.code === "23505" ? "withdrawal_pending" : "invalid_input" },
        reserveError.code === "23505" ? 409 : 422);
      return reply({ withdrawal: publicRow(data as Row), swapTxns: quote.swapTxns }, 201);
    }
    const id = submitMatch?.[1] ?? cancelMatch?.[1];
    if (!uuid(id)) return reply({ error: "not_found" }, 404);
    const { data, error: readError } = await client.from("bsmart_across_withdrawals")
      .select("*").eq("account_id", user.id).eq("id", id).maybeSingle();
    if (readError || !data || data.wallet_address !== owner) return reply({ error: "not_found" }, 404);
    let row = data as Row;
    if (cancelMatch) {
      if (row.state !== "quoted") return reply({ error: "withdrawal_pending" }, 409);
      row = await change(client, row, "quoted", "cancelled");
      return reply({ withdrawal: publicRow(row) });
    }
    if (row.state !== "quoted" || Date.parse(row.quote_expires_at) <= Date.now() + 5_000) {
      return reply({ error: "quote_expired" }, 409);
    }
    const input = await json(req, 2048);
    if (!record(input) || Object.keys(input).join() !== "signaturesByStepId" ||
        !await signedSteps(row.quote, input.signaturesByStepId, owner)) {
      return reply({ error: "invalid_signature" }, 422);
    }
    try { row = await change(client, row, "quoted", "submitting", { attempted_at: new Date().toISOString() }); }
    catch { return reply({ error: "withdrawal_pending" }, 409); }
    let outcome = "uncertain", providerResponse: unknown = null;
    try {
      providerResponse = await provider.submit({
        swapTx: row.quote.swapTx, swapTxns: row.quote.swapTxns,
        signaturesByStepId: input.signaturesByStepId,
      });
      if (record(providerResponse) && String(providerResponse.depositId) === row.deposit_id) outcome = "submitted";
    } catch { /* An ambiguous submit must never be replayed. */ }
    try {
      row = await change(client, row, "submitting", outcome, {
        provider_response: providerResponse && JSON.stringify(providerResponse).length <= 4096 ? providerResponse : null,
      });
    } catch { return reply({ error: "withdrawal_pending" }, 503); }
    return reply({ withdrawal: publicRow(row) });
  } catch { return reply({ error: "withdrawal_unavailable" }, 503); }
}
