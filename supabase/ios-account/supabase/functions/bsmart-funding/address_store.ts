import type { SupabaseClient } from "npm:@supabase/supabase-js@2.116.0";
import { networks, PERPS, validAddress, type Network, type RelayFunding } from "./relay.ts";

const columns = "account_id,wallet_address,network,origin_chain_id,origin_currency,destination_chain_id,destination_currency,deposit_address,request_id,created_at";

function checked(row: Record<string, unknown> | null, account: string, owner: string, network: Network) {
  const source = networks[network];
  if (!row || row.account_id !== account || row.wallet_address !== owner || row.network !== network ||
      row.origin_chain_id !== source.chainId || row.origin_currency !== source.token ||
      row.destination_chain_id !== 1337 || row.destination_currency !== PERPS ||
      !validAddress(row.deposit_address) || row.deposit_address === owner ||
      !/^0x[0-9a-f]{64}$/.test(String(row.request_id)) ||
      typeof row.created_at !== "string" || !Number.isFinite(Date.parse(row.created_at))) {
    throw new Error("invalid_saved_deposit_route");
  }
  return { network, recipient: owner, refundAddress: owner, depositAddress: row.deposit_address,
    reusable: true, createdAt: row.created_at };
}

export async function stableAddress(client: SupabaseClient, provider: RelayFunding,
  account: string, owner: string, network: Network) {
  const lookup = () => client.from("bsmart_funding_addresses").select(columns)
    .eq("account_id", account).eq("wallet_address", owner).eq("network", network).maybeSingle();
  const existing = await lookup();
  if (existing.error) throw new Error("funding_address_store_unavailable");
  if (existing.data) return checked(existing.data, account, owner, network);

  const fresh = await provider.address(owner, network);
  if (fresh.recipient !== owner || fresh.refundAddress !== owner || fresh.network !== network ||
      !validAddress(fresh.depositAddress) || fresh.depositAddress === owner ||
      !/^0x[0-9a-f]{64}$/.test(fresh.requestId)) throw new Error("invalid_provider_route");
  const source = networks[network];
  const registration = await client.from("bsmart_funding_addresses").upsert({
    account_id: account, wallet_address: owner, network,
    origin_chain_id: source.chainId, origin_currency: source.token,
    destination_chain_id: 1337, destination_currency: PERPS,
    deposit_address: fresh.depositAddress, request_id: fresh.requestId.toLowerCase(),
  }, { onConflict: "account_id,wallet_address,network", ignoreDuplicates: true });
  if (registration.error) throw new Error("funding_address_store_unavailable");
  // A concurrent first request may have won the unique key. Return only the
  // committed address, never a second provider quote that was not registered.
  const saved = await lookup();
  if (saved.error) throw new Error("funding_address_store_unavailable");
  return checked(saved.data, account, owner, network);
}
