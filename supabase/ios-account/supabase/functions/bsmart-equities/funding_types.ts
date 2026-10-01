import type { ChainState } from "./quote.ts";
import type { EVMInstrument } from "./routing.ts";
import { NETWORKS } from "./assets.ts";

export const HC_PERPS = "0x00000000000000000000000000000000";
export const HC_SPOT = "0x6d1e7cde53ba9467b783cb7c530ce054";
export const FUNDING_CURRENCIES = {
  HyperCorePerps: { chainId: 1337, address: HC_PERPS, decimals: 8, protocolChain: "hyperliquid" },
  HyperCoreSpot: { chainId: 1337, address: HC_SPOT, decimals: 8, protocolChain: "hyperliquid" },
  Ethereum: { chainId: 1, address: NETWORKS.Ethereum.usdc, decimals: 6, protocolChain: "ethereum" },
  Ink: { chainId: 57073, address: NETWORKS.Ink.usdc, decimals: 6, protocolChain: "ink" },
} as const;
export type FundingSource = keyof typeof FUNDING_CURRENCIES;
export type BridgeRequest = { owner: string; source: FundingSource; destination: "HyperCorePerps" | EVMInstrument["network"]; amountRaw: string };
export type BridgeQuote = {
  provider: "relay"; source: FundingSource; destination: BridgeRequest["destination"];
  inputAmountRaw: string; inputDecimals: 6 | 8; expectedOutputAmountRaw: string; minimumOutputAmountRaw: string;
  outputDecimals: 6 | 8; maximumLossUsdcRaw: string; originNativeGasRequired: boolean;
  mechanism: "hypercore_nonce_mapping" | "permit_candidate" | "evm_transaction";
  refundNetworks: FundingSource[]; observedAt: string; expiresAt: string;
};
export type HCFunds = { owner: string; mode: string; source: "HyperCorePerps" | "HyperCoreSpot";
  availableRaw: string; at: number; flatAccountChecked: boolean };
export type FundingPorts = {
  state: (instrument: EVMInstrument, owner: string) => Promise<ChainState>;
  hypercore: (owner: string) => Promise<HCFunds>;
  bridge: (request: BridgeRequest) => Promise<BridgeQuote>;
  assertIdle: (account: string, owner: string, intentId: string) => Promise<void>;
};
export type FundingPlan = { instrument: EVMInstrument; orderFingerprint: string; executionChainUsdcRaw: string;
  deficitUsdcRaw: string; source: "execution_chain" | "hyperliquid" | "sale_proceeds";
  saleProceedsBasis: "quoted_minimum" | null; bridge: BridgeQuote | null; costBoundUsdcRaw: string;
  costScope: "buy_cow_network_and_bridge" | "sell_bridge_only"; expiresAt: string; blockers: string[] };

export const floorMicro = (value: bigint, decimals: 6 | 8) => decimals === 8 ? value / 100n : value;
export const ceilMicro = (value: bigint, decimals: 6 | 8) => decimals === 8 ? (value + 99n) / 100n : value;
