export {
  SmartVoiceCreatorModule,
  SmartVoiceLeaderboard,
  SmartVoicePortfolioModule,
  SmartVoiceTickerModule,
} from "./components/SmartVoiceModules";
export { SmartVoiceInvestorProfile } from "./components/SmartVoiceInvestorProfile";
export { PublicSmartVoiceLeaderboard } from "./components/PublicSmartVoiceLeaderboard";
export { SmartVoiceScore } from "./components/SmartVoicePrimitives";
export { SmartVoiceWorkspace } from "./components/SmartVoiceWorkspace";
export { HyperliquidSmartMoneyView } from "./components/HyperliquidSmartMoneyView";
export * from "./hyperliquidData";
export * from "./svInvestorLinks";
export * from "./svMock";

// Canonical product exports. The SmartVoice names remain temporary aliases for
// legacy imports and serialized data adapters.
export { SmartVoiceInvestorProfile as SmartAccountInvestorProfile } from "./components/SmartVoiceInvestorProfile";
export { PublicSmartVoiceLeaderboard as PublicSmartAccountLeaderboard } from "./components/PublicSmartVoiceLeaderboard";
export { SmartVoiceWorkspace as SmartAccountWorkspace } from "./components/SmartVoiceWorkspace";
