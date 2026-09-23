const API = "https://api.relay.link";
export const PERPS = "0x00000000000000000000000000000000";
export const networks = {
  arbitrum: { chainId: 42161, token: "0xaf88d065e77c8cc2239327c5edb3a432268e5831", decimals: 6 },
  monad: { chainId: 143, token: "0x754704bc059f8c67012fed69bc8a327a5aafb603", decimals: 6 },
  base: { chainId: 8453, token: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913", decimals: 6 },
  ethereum: { chainId: 1, token: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", decimals: 6 },
  bnb: { chainId: 56, token: "0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d", decimals: 18 },
} as const;
export type Network = keyof typeof networks;
export const validAddress = (s: unknown): s is string => typeof s === "string" &&
  /^0x[0-9a-fA-F]{40}$/.test(s) && !/^0x0{40}$/.test(s);
const object = (v: unknown): Record<string, any> => {
  if (!v || typeof v !== "object" || Array.isArray(v)) throw new Error("invalid_provider_response");
  return v as Record<string, any>;
};
const same = (a: unknown, b: string) => typeof a === "string" && a.toLowerCase() === b.toLowerCase();
const decimal = (s: unknown) => typeof s === "string" && /^\d{1,20}(\.\d{1,18})?$/.test(s);

export function amountMicro(value: unknown): string {
  return amountUnits(value, 6);
}

export function amountUnits(value: unknown, decimals: 6 | 18): string {
  if (typeof value !== "string" || !/^(0|[1-9]\d{0,6})(\.\d{1,6})?$/.test(value)) throw new Error("invalid_amount");
  const [whole, fraction = ""] = value.split(".");
  const amount = BigInt(whole) * 10n ** BigInt(decimals) + BigInt(fraction.padEnd(decimals, "0"));
  if (amount <= 0n) throw new Error("invalid_amount");
  return amount.toString();
}

export function quoteBody(owner: string, network: Network, amount: string) {
  if (!validAddress(owner) || !Object.hasOwn(networks, network)) throw new Error("invalid_route");
  const source = networks[network];
  return {
    user: owner, recipient: owner, refundTo: owner,
    originChainId: source.chainId, originCurrency: source.token,
    destinationChainId: 1337, destinationCurrency: PERPS,
    amount: amountUnits(amount, source.decimals), tradeType: "EXACT_INPUT",
    useDepositAddress: true, strict: false, slippageTolerance: "50",
  };
}

export function parseQuote(value: unknown, owner: string, network: Network, amount: string) {
  const v = object(value), d = object(v.details), input = object(d.currencyIn), output = object(d.currencyOut);
  const source = networks[network];
  if (!same(d.recipient, owner) || !same(d.sender, owner) ||
      input.currency?.chainId !== source.chainId || !same(input.currency?.address, source.token) ||
      input.currency?.decimals !== source.decimals || input.amount !== amountUnits(amount, source.decimals) ||
      output.currency?.chainId !== 1337 || !same(output.currency?.address, PERPS) ||
      output.currency?.decimals !== 8 || !decimal(output.amountFormatted) ||
      !/^[1-9]\d*$/.test(output.amount ?? "") || !/^\d+$/.test(output.minimumAmount ?? "") ||
      BigInt(output.minimumAmount) <= 0n || BigInt(output.minimumAmount) > BigInt(output.amount) ||
      !Array.isArray(v.steps) || v.steps.length !== 1) throw new Error("invalid_provider_response");
  const step = object(v.steps[0]);
  if (step.id !== "deposit" || step.kind !== "transaction" || !validAddress(step.depositAddress) ||
      same(step.depositAddress, owner) || same(step.depositAddress, source.token) ||
      !/^0x[0-9a-fA-F]{64}$/.test(step.requestId ?? "")) throw new Error("invalid_provider_response");
  return {
    network, recipient: owner, refundAddress: owner, depositAddress: step.depositAddress.toLowerCase(),
    requestId: step.requestId, inputAmount: amount,
    estimatedOutput: output.amountFormatted, quotedAt: new Date().toISOString(),
  };
}

export function parseDeposits(value: unknown, owner: string) {
  const v = object(value);
  if (!Array.isArray(v.requests) || v.requests.length > 20) throw new Error("invalid_provider_response");
  return v.requests.flatMap((raw: unknown) => {
    const r = object(raw);
    if (!same(r.recipient, owner)) throw new Error("invalid_provider_response");
    // v3 separates quoted and actual routes. Never report a quote as a settled amount.
    const quoted = r.data?.route?.quoted?.destination?.outputCurrency;
    const actual = r.data?.route?.actual?.destination?.outputCurrency;
    const route = actual ?? quoted;
    if (!route) throw new Error("invalid_provider_response");
    if (route.currency?.chainId !== 1337 || !same(route.currency?.address, PERPS)) return [];
    if (!r.depositAddress || !validAddress(r.depositAddress.address)) return [];
    if (!/^0x[0-9a-fA-F]{64}$/.test(r.id ?? "") || typeof r.createdAt !== "string" ||
        !Number.isFinite(Date.parse(r.createdAt))) throw new Error("invalid_provider_response");
    const states = ["waiting", "depositing", "pending", "submitted", "delayed", "success", "refund", "failure"];
    return [{ id: r.id, status: states.includes(r.status) ? r.status : "unknown",
      createdAt: r.createdAt, amount: r.status === "success" && decimal(actual?.amountFormatted)
        ? actual.amountFormatted : null }];
  });
}

export class RelayFunding {
  constructor(private key: string, private fetcher: typeof fetch = fetch) {}

  private async request(path: string, body?: unknown): Promise<unknown> {
    if (!this.key) throw new Error("provider_unconfigured");
    const response = await this.fetcher(API + path, {
      method: body ? "POST" : "GET", redirect: "error",
      headers: { "x-api-key": this.key, "Content-Type": "application/json" },
      body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(12000),
    });
    if (!response.ok) { await response.body?.cancel(); throw new Error("provider_unavailable"); }
    // Bound untrusted provider payloads, including streaming/chunked responses.
    const reader = response.body?.getReader();
    if (!reader) throw new Error("invalid_provider_response");
    const chunks: Uint8Array[] = []; let size = 0;
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        size += value.length;
        if (size > 2_097_152) throw new Error("invalid_provider_response");
        chunks.push(value);
      }
    } finally { await reader.cancel(); }
    const data = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { data.set(chunk, offset); offset += chunk.length; }
    return JSON.parse(new TextDecoder().decode(data));
  }

  async quote(owner: string, network: Network, amount: string) {
    return parseQuote(await this.request("/quote/v2", quoteBody(owner, network, amount)), owner, network, amount);
  }

  async address(owner: string, network: Network) {
    // Relay requires an initial quote to register an open address. This is not a
    // payment instruction or minimum: each actual deposit is priced on receipt.
    const quote = await this.quote(owner, network, "20");
    return { network: quote.network, recipient: quote.recipient, refundAddress: quote.refundAddress,
      depositAddress: quote.depositAddress, requestId: quote.requestId,
      reusable: true, createdAt: quote.quotedAt };
  }

  async deposits(owner: string) {
    const query = new URLSearchParams({ recipient: owner, destinationChainId: "1337", limit: "20" });
    return parseDeposits(await this.request("/requests/v3?" + query), owner);
  }
}
