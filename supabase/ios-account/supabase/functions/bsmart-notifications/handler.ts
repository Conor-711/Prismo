type User = { id: string; is_anonymous?: boolean; app_metadata?: { provider?: string; providers?: string[] } };
export interface NotificationBackend {
  getUser(token: string): Promise<{ user: User | null; unavailable?: boolean }>;
  rpc(name: string, parameters: Record<string, unknown>): Promise<boolean>;
}
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), {
  status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" },
});
async function body(request: Request): Promise<Record<string, unknown>> {
  const reader = request.body?.getReader();
  if (!reader) throw new Error("body");
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      length += chunk.value.length;
      if (length > 16384) throw new Error("length");
      chunks.push(chunk.value);
    }
  } finally { await reader.cancel(); }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  const result = JSON.parse(new TextDecoder().decode(bytes));
  if (!result || Array.isArray(result) || typeof result !== "object") throw new Error("object");
  return result;
}
export async function handleNotifications(request: Request, backend: NotificationBackend): Promise<Response> {
  const path = new URL(request.url).pathname;
  const device = path.endsWith("/bsmart-notifications/device");
  const interests = path.endsWith("/bsmart-notifications/interests");
  if (!device && !interests) return reply(404, { error: "not_found" });
  if (interests ? request.method !== "PUT" : !["PUT", "DELETE"].includes(request.method)) {
    return reply(405, { error: "method_not_allowed" });
  }
  const token = request.headers.get("Authorization")?.match(/^Bearer ([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)$/)?.[1];
  if (!token || token.length > 8192) return reply(401, { error: "unauthorized" });
  try {
    const { user, unavailable } = await backend.getUser(token);
    if (unavailable) return reply(503, { error: "unavailable" });
    const providers = user?.app_metadata?.providers ?? [user?.app_metadata?.provider];
    if (!user || user.is_anonymous || !uuid.test(user.id) || !providers.some(p => p === "apple" || p === "google")) {
      return reply(401, { error: "unauthorized" });
    }
    let input: Record<string, unknown>;
    try { input = await body(request); } catch { return reply(422, { error: "invalid_device" }); }
    if (typeof input.installationId !== "string" || !uuid.test(input.installationId)) return reply(422, { error: "invalid_device" });
    const parameters: Record<string, unknown> = { p_user: user.id, p_installation: input.installationId };
    if (interests) {
      const stringSet = (value: unknown, ticker = false): string[] | null => {
        if (!Array.isArray(value) || value.length > 150 || value.some(item =>
          typeof item !== "string" || item.length < 1 || item.length > 160 || /[\x00-\x1f\x7f]/.test(item))) return null;
        return [...new Set(value.map(item => ticker ? item.trim().toUpperCase() : item.trim().toLowerCase()))]
          .filter(Boolean);
      };
      const authors = stringSet(input.authors), money = stringSet(input.money);
      const tickers = stringSet(input.tickers, true), holdings = stringSet(input.holdings, true);
      if (!authors || !money || !tickers || !holdings ||
          typeof input.notifyAuthors !== "boolean" || typeof input.notifyTickers !== "boolean" ||
          typeof input.notifyHoldings !== "boolean") return reply(422, { error: "invalid_interests" });
      const ok = await backend.rpc("bsmart_set_push_interests", {
        ...parameters, p_authors: authors, p_money: money, p_tickers: tickers, p_holdings: holdings,
        p_notify_authors: input.notifyAuthors, p_notify_tickers: input.notifyTickers,
        p_notify_holdings: input.notifyHoldings,
      });
      return ok ? reply(200, { registered: true }) : reply(503, { error: "unavailable" });
    }
    const register = request.method === "PUT";
    if (register) {
      if (typeof input.apnsToken !== "string" || !/^[a-f0-9]{64,200}$/.test(input.apnsToken)
          || !["development", "production"].includes(String(input.environment))
          || typeof input.enabled !== "boolean" || typeof input.locale !== "string"
          || !/^[A-Za-z0-9_@=;-]{1,64}$/.test(input.locale)) return reply(422, { error: "invalid_device" });
      Object.assign(parameters, { p_token: input.apnsToken, p_environment: input.environment, p_locale: input.locale, p_enabled: input.enabled });
    }
    const ok = await backend.rpc(register ? "bsmart_register_push" : "bsmart_unregister_push", parameters);
    return ok ? reply(200, { registered: register }) : reply(503, { error: "unavailable" });
  } catch { return reply(503, { error: "unavailable" }); }
}
