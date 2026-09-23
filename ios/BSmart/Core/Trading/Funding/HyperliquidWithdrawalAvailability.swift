import Foundation

struct HyperliquidWithdrawalAvailability: Sendable {
    let balance: HyperCoreBalanceSnapshot
    var flatAccount: HyperliquidFlatAccountProof?

    var source: HyperliquidWithdrawalIntent.Source {
        balance.mode == .unifiedAccount ? .spot : .perps
    }

    func availableUnits(wallet: DeviceWalletSummary, now: Date) throws -> FundingQuantity {
        try balance.validate(wallet: wallet, now: now)
        if source == .spot {
            guard let flatAccount, balance.held.units == FundingQuantity(0) else {
                throw HyperliquidWithdrawalError.unsupportedBalance
            }
            try flatAccount.validate(owner: wallet.address, now: now)
            return balance.usdc.units
        }
        guard !balance.mode.usesSharedBalance, let perps = balance.perps else {
            throw HyperliquidWithdrawalError.unsupportedBalance
        }
        return perps.withdrawable.units
    }

    func maximumAmount(wallet: DeviceWalletSummary, now: Date) throws -> String {
        guard let units = try availableUnits(wallet: wallet, now: now).uint64 else {
            throw HyperliquidWithdrawalError.invalidResponse
        }
        // HyperCore has eight decimals; round down to CCTP's six, never above the balance.
        return FundingQuantity(units / 100).formatted(decimals: 6)
    }
}
