import { importPKCS8, SignJWT } from "npm:jose@5.10.0";
import type { Delivery, Result, Sender } from "./handler.ts";

type Config = { team: string; keyId: string; privateKey: string; topic: string };
export type ProviderCache = {
  exchange(identity: string, candidate?: string): Promise<{ token: string; expires_at: string } | null>;
};
export function digestPayload(delivery: Delivery) {
  const zh = delivery.locale.toLowerCase().startsWith("zh");
  return { type: "content_digest", slotAt: delivery.slot_at, aps: {
    alert: { title: zh ? "bSmart 新动态" : "New on bSmart",
      body: zh ? `你关注的作者或资产有 ${delivery.item_count} 条新观点或动态。` :
        `${delivery.item_count} new views or updates from authors and assets you follow.` },
    sound: "default", "thread-id": "bsmart.content-digest",
  } };
}
export function apnsSender(config: Config, fetcher: typeof fetch, now = Date.now, cache?: ProviderCache,
  payloadFactory: (delivery: Delivery) => unknown = digestPayload): Sender {
  let cached: string | undefined, issuedAt = 0, expiresAt = 0;
  async function token() {
    if (!/^[A-Z0-9]{10}$/.test(config.team) || !/^[A-Z0-9]{10}$/.test(config.keyId) || config.topic !== "today.bsmart.ios") throw Error("configuration");
    if (!cached || now() < issuedAt || now() >= expiresAt) {
      const identity = `${config.team}:${config.keyId}:${config.topic}`;
      const stored = await cache?.exchange(identity);
      if (stored && Date.parse(stored.expires_at) > now()) {
        cached = stored.token; issuedAt = now(); expiresAt = Date.parse(stored.expires_at);
        return cached;
      }
      const key = await importPKCS8(config.privateKey.replace(/\\n/g, "\n"), "ES256");
      const candidate = await new SignJWT({}).setProtectedHeader({ alg: "ES256", kid: config.keyId })
        .setIssuer(config.team).setIssuedAt(Math.floor(now() / 1000)).sign(key);
      const selected = await cache?.exchange(identity, candidate);
      if (cache && (!selected || Date.parse(selected.expires_at) <= now())) throw Error("provider_cache");
      cached = selected?.token ?? candidate;
      expiresAt = selected ? Date.parse(selected.expires_at) : now() + 45 * 60_000;
      issuedAt = now();
    }
    return cached;
  }
  return {
    async ready() { await token(); },
    async send(delivery): Promise<Result> {
      const slot = Date.parse(delivery.slot_at);
      const expiration = delivery.notice ? Date.parse(delivery.notice.expiresAt) : slot + 30 * 60_000;
      if (delivery.environment !== "production" || !/^[a-f0-9]{64,200}$/.test(delivery.apns_token) ||
        !Number.isSafeInteger(delivery.item_count) || delivery.item_count <= 0 || !Number.isFinite(slot) ||
        !Number.isFinite(expiration) || expiration > slot + 24 * 60 * 60_000 ||
        now() < slot || now() >= expiration) return { status: null, invalid: false };
      try {
        const body = JSON.stringify(payloadFactory(delivery));
        if (new TextEncoder().encode(body).length > 4096) return { status: null, invalid: false };
        const response = await fetcher("https://api.push.apple.com/3/device/" + delivery.apns_token, {
          method: "POST", redirect: "error", signal: AbortSignal.timeout(8000),
          headers: { authorization: "bearer " + await token(), "apns-topic": config.topic,
            "apns-id": delivery.apns_id, "apns-push-type": "alert", "apns-priority": "10",
            "apns-expiration": String(Math.floor(expiration / 1000)),
            "apns-collapse-id": delivery.notice ? "bsmart." + delivery.notice.id :
              "bsmart." + Math.floor(slot / 1000) + "." + delivery.user_id },
          body,
        });
        let reason = "";
        if (response.status !== 200) {
          const text = await response.text();
          if (text.length <= 4096) { try { reason = JSON.parse(text).reason ?? ""; } catch { /* No upstream diagnostics exposed. */ } }
        } else await response.body?.cancel();
        return { status: response.status, invalid: [400, 410].includes(response.status) &&
          ["BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered", "ExpiredToken"].includes(reason) };
      } catch { return { status: null, invalid: false }; }
    },
  };
}
