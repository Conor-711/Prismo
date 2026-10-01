// Reproducible public key-1 vectors. Offline only; not production signing.
import { context, at, signer } from "../tests/fixtures/equity_cow.ts";
import { cowTypedData, prepareCowOrder } from "../supabase/functions/bsmart-equities/cow_order.ts";
import { validateQuoteArtifacts } from "../supabase/functions/bsmart-equities/quote.ts";
import { preparationHash } from "../supabase/functions/bsmart-equities/preparations.ts";
const vectors = [];
for (const network of ["Ethereum", "Ink", "Ethereum"] as const) {
  const c = await context("buy", network);
  if (vectors.length === 2) {
    const response = { ...c.response, quote: { ...c.response.quote, buyAmount: "2000000000000000000000" } };
    const { preview, material } = await validateQuoteArtifacts(response, c.request, c.instrument, c.input, c.state, c.row.account_id, at);
    c.material = material;
    c.prepared = await prepareCowOrder(material, { ...c.row, preview: { ...c.row.preview!, candidates: [preview] } }, 1, c.state, at, c.row.wallet_address);
  }
  const typed = cowTypedData(c.prepared);
  const payload = { schema: "equity_signing_v1", state: "signing", signingStartedAt: new Date(at).toISOString(),
    preparationHash: await preparationHash(c.material, c.prepared), prepared: c.prepared, executionEnabled: false };
  const typedData = { ...typed, types: { EIP712Domain: [
    { name: "name", type: "string" }, { name: "version", type: "string" },
    { name: "chainId", type: "uint256" }, { name: "verifyingContract", type: "address" },
  ], ...typed.types } };
  vectors.push({ payload, typedData, signature: await signer.signTypedData({ ...typed, domain: typed.domain as any }),
    ethSignSignature: await signer.signMessage({ message: { raw: c.prepared.orderDigest as `0x${string}` } }) });
}
await Deno.writeTextFile(new URL("../../../contracts/fixtures/evm-equity-signing.json", import.meta.url),
  JSON.stringify({ testOnly: true, source: "Pinned official CoW SDK + viem, disposable public key 1", vectors }, null, 2) + "\n");
console.log(JSON.stringify({ vectors: vectors.length, networks: vectors.map(v => v.payload.prepared.instrument.network), ordersSubmitted: false }));
