import { createPublicClient, erc20Abi, fallback, http, parseAbi } from "npm:viem@2.56.3";
import { ink, mainnet } from "npm:viem@2.56.3/chains";
import { COW_PROTOCOL_VAULT_RELAYER_ADDRESS, SupportedChainId } from "npm:@cowprotocol/sdk-config@2.7.2";
import { MarketError } from "../bsmart-markets/routing.ts";
import { address, type ChainState } from "./quote.ts";
import type { EVMInstrument } from "./routing.ts";

// Issuer reference ABI, not a sharesOf-to-balance conversion. balanceOf is already adjusted.
const rebasingAbi = parseAbi([
  "function getCurrentMultiplier() view returns (uint256 currentMultiplier, uint256 periodsPassed, uint256 currentMultiplierNonce)",
  "function newMultiplierActivationTime() view returns (uint256)",
]);
export function chainReader(rpcs: Partial<Record<"Ethereum" | "Ink", string>> = {}, now: () => number = Date.now, fetcher: typeof fetch = fetch) {
  const makeClient = (network: EVMInstrument["network"]) => {
    const chain = network === "Ink" ? ink : mainnet;
    // Public defaults are development probes. Prefer a configured managed RPC for rollout.
    // Ink's second official endpoint passed the public probe; both remain read-only fallbacks.
    const endpoints = rpcs[network] ? [rpcs[network]!] : network === "Ink"
      ? [...chain.rpcUrls.default.http].reverse() : [...chain.rpcUrls.default.http];
    if (endpoints.some(endpoint => new URL(endpoint).protocol !== "https:")) throw Error("invalid_rpc");
    return createPublicClient({ transport: fallback(endpoints.map(endpoint => http(endpoint, {
      timeout: 8000, retryCount: 0, fetchFn: fetcher, fetchOptions: { redirect: "error" },
    })), { retryCount: 0 }) });
  };
  const clients = new Map<string, ReturnType<typeof makeClient>>();
  return async (instrument: EVMInstrument, owner: string): Promise<ChainState> => {
    try {
      let client = clients.get(instrument.network);
      if (!client) {
        client = makeClient(instrument.network);
        clients.set(instrument.network, client);
      }
      const at = now();
      if (await client.getChainId() !== instrument.chainId) throw Error("rpc_chain_mismatch");
      const block = await client.getBlock({ blockTag: "latest" });
      const blockNumber = block.number;
      if (blockNumber === null) throw Error("missing_block");
      const token = address(instrument.token) as `0x${string}`, usdc = address(instrument.usdc) as `0x${string}`;
      const account = address(owner) as `0x${string}`;
      const spender = address(COW_PROTOCOL_VAULT_RELAYER_ADDRESS[instrument.network === "Ink" ? SupportedChainId.INK : SupportedChainId.MAINNET]) as `0x${string}`;
      const erc = { abi: erc20Abi, blockNumber };
      const [tokenDecimals, usdcDecimals, tokenBalance, usdcBalance, tokenAllowance, usdcAllowance, multiplier, activation] = await Promise.all([
        client.readContract({ ...erc, address: token, functionName: "decimals" }),
        client.readContract({ ...erc, address: usdc, functionName: "decimals" }),
        client.readContract({ ...erc, address: token, functionName: "balanceOf", args: [account] }),
        client.readContract({ ...erc, address: usdc, functionName: "balanceOf", args: [account] }),
        client.readContract({ ...erc, address: token, functionName: "allowance", args: [account, spender] }),
        client.readContract({ ...erc, address: usdc, functionName: "allowance", args: [account, spender] }),
        client.readContract({ address: token, abi: rebasingAbi, functionName: "getCurrentMultiplier", blockNumber }),
        client.readContract({ address: token, abi: rebasingAbi, functionName: "newMultiplierActivationTime", blockNumber }),
      ]);
      return { at, chainId: instrument.chainId, owner: account, token, usdc, block: blockNumber.toString(),
        blockTimestamp: Number(block.timestamp), tokenDecimals: Number(tokenDecimals), usdcDecimals: Number(usdcDecimals),
        tokenBalance: String(tokenBalance), usdcBalance: String(usdcBalance), tokenAllowance: String(tokenAllowance), usdcAllowance: String(usdcAllowance),
        multiplier: multiplier[0].toString(), multiplierNonce: multiplier[2].toString(), activationTime: Number(activation) };
    } catch { throw new MarketError("chain_state_unavailable"); }
  };
}
