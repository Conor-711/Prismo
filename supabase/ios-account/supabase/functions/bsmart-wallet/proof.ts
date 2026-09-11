import { verifyMessage } from "npm:viem@2.56.3";

export type Challenge = {
  id: string; accountId: string; address: string; nonce: string; issuedAt: string; expiresAt: string;
};

export const validAddress = (value: unknown): value is `0x${string}` =>
  typeof value === "string" && /^0x[0-9a-f]{40}$/.test(value) && !/^0x0{40}$/.test(value);

export function bindingMessage(c: Challenge, accountId: string, now = Date.now()): string {
  const issued = Date.parse(c.issuedAt), expires = Date.parse(c.expiresAt);
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
  const utc = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
  if (c.accountId !== accountId || !uuid.test(c.id) || !uuid.test(c.accountId) || !validAddress(c.address) ||
      !/^[0-9a-f]{64}$/.test(c.nonce) || !utc.test(c.issuedAt) || !utc.test(c.expiresAt) ||
      !Number.isFinite(issued) || !Number.isFinite(expires) || issued > now + 30000 || expires <= now ||
      expires <= issued || expires - issued > 300000 || now - issued >= 300000) throw new Error("invalid_proof");
  return [
    "bSmart wallet binding v1",
    "Audience: https://api.bsmart.today/v1/auth/wallet",
    `Account: ${c.accountId}`, `Address: ${c.address}`, "Chain ID: 42161",
    `Challenge: ${c.id}`, `Nonce: ${c.nonce}`, `Issued At: ${c.issuedAt}`, `Expires At: ${c.expiresAt}`,
    "This only links your wallet to bSmart. It does not authorize a transfer or trade.",
  ].join("\n");
}

export async function verifyBinding(c: Challenge, account: string, signature: string, now = Date.now()): Promise<boolean> {
  if (!/^0x[0-9a-fA-F]{130}$/.test(signature)) return false;
  try {
    return await verifyMessage({ address: c.address as `0x${string}`, message: bindingMessage(c, account, now),
                                 signature: signature as `0x${string}` });
  } catch { return false; }
}
