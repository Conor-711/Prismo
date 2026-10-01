import { MarketError } from "../bsmart-markets/routing.ts";

export async function jsonBody(req: Request): Promise<unknown> {
  if (new URL(req.url).search || !/^application\/json(?:\s*;|$)/i.test(req.headers.get("content-type") ?? "")) throw new MarketError("invalid_preview", 422);
  const reader = req.body?.getReader();
  if (!reader) throw new MarketError("invalid_preview", 422);
  const chunks: Uint8Array[] = []; let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 4096) throw new MarketError("body_too_large", 413);
      chunks.push(value);
    }
  } finally { await reader.cancel().catch(() => {}); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  try { return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)); }
  catch { throw new MarketError("invalid_preview", 422); }
}
