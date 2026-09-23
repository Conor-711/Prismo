import Foundation

struct HyperCoreUSDCAmount: Equatable, Sendable {
    let units: FundingQuantity
    let isNegative: Bool

    init(_ text: String, signed: Bool = false) throws {
        guard !text.isEmpty, text.utf8.count <= 30 else { throw HyperCoreBalanceError.invalidResponse }
        let negative = text.hasPrefix("-")
        guard signed || !negative else { throw HyperCoreBalanceError.invalidResponse }
        let digits = negative ? String(text.dropFirst()) : text
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), !parts[0].isEmpty,
              parts[0].count == 1 || parts[0].first != "0",
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy({ (48...57).contains($0) }) }),
              parts.count == 1 || parts[1].count <= 8 else { throw HyperCoreBalanceError.invalidResponse }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        let scaled = (String(parts[0]) + fraction + String(repeating: "0", count: 8 - fraction.count))
            .drop(while: { $0 == "0" })
        units = try FundingQuantity(decimal: scaled.isEmpty ? "0" : String(scaled))
        guard units.uint64 != nil else { throw HyperCoreBalanceError.invalidResponse }
        isNegative = negative && units != FundingQuantity(0)
    }

    var formatted: String { (isNegative ? "-" : "") + units.formatted(decimals: 8) }
}

enum HyperCoreAccountMode: String, CaseIterable, Sendable {
    case `default`, disabled, dexAbstraction, unifiedAccount, portfolioMargin

    var usesSharedBalance: Bool { self == .unifiedAccount || self == .portfolioMargin }
    var title: String {
        switch self {
        case .default: return "Protocol default".bSmartLocalized
        case .disabled: return "Separate balances".bSmartLocalized
        case .dexAbstraction: return "DEX abstraction".bSmartLocalized
        case .unifiedAccount: return "Unified account".bSmartLocalized
        case .portfolioMargin: return "Portfolio margin".bSmartLocalized
        }
    }
}

struct HyperCorePerpsBalance: Equatable, Sendable {
    let equity: HyperCoreUSDCAmount
    let withdrawable: HyperCoreUSDCAmount
    let updatedAt: Date
}

struct HyperCoreBalanceSnapshot: Equatable, Sendable {
    let accountID: UUID
    let owner: String
    let mode: HyperCoreAccountMode
    let usdc: HyperCoreUSDCAmount
    let held: HyperCoreUSDCAmount
    let perps: HyperCorePerpsBalance?
    let requestedAt: Date
    let checkedAt: Date

    var accountBalanceValue: Double? {
        guard let cash = Double(usdc.formatted), cash.isFinite else { return nil }
        guard let perps else { return cash }
        guard let equity = Double(perps.equity.formatted), equity.isFinite else { return nil }
        let total = cash + equity
        return total.isFinite ? total : nil
    }

    var expiresAt: Date {
        min(requestedAt.addingTimeInterval(30), perps?.updatedAt.addingTimeInterval(30) ?? requestedAt.addingTimeInterval(30))
    }

    func validate(wallet: DeviceWalletSummary, now: Date) throws {
        guard accountID == wallet.accountID, owner == wallet.address, TradingWalletChallenge.validAddress(owner),
              !usdc.isNegative, !held.isNegative, held.units <= usdc.units,
              mode.usesSharedBalance == (perps == nil), perps?.withdrawable.isNegative != true else {
            throw HyperCoreBalanceError.invalidResponse
        }
        guard requestedAt.timeIntervalSince1970.isFinite, checkedAt.timeIntervalSince1970.isFinite,
              checkedAt >= requestedAt, now >= checkedAt, now < expiresAt else { throw HyperCoreBalanceError.stale }
        if let perps {
            let age = checkedAt.timeIntervalSince(perps.updatedAt)
            guard age.isFinite, age >= -15, age < 30 else { throw HyperCoreBalanceError.stale }
        }
    }
}

enum HyperCoreBalanceError: Error, LocalizedError, Equatable {
    case unavailable, invalidResponse, stale, accountChanged

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Hyperliquid balances could not be checked. No transfer was made.".bSmartLocalized
        case .invalidResponse: return "Hyperliquid balance data could not be verified.".bSmartLocalized
        case .stale: return "The balance check expired or the account mode changed. Refresh to check again.".bSmartLocalized
        case .accountChanged: return "The registered wallet changed. Unlock the current wallet again.".bSmartLocalized
        }
    }
}
