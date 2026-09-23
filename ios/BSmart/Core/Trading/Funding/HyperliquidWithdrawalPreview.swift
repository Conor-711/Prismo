import Foundation

struct HyperliquidWithdrawalPreview: Sendable {
    let intent: HyperliquidWithdrawalIntent
    let balance: HyperCoreBalanceSnapshot
    let fee: CCTPWithdrawalFeeSnapshot
    var flatAccount: HyperliquidFlatAccountProof? = nil

    var available: String { intent.source == .spot ? balance.usdc.formatted : (balance.perps?.withdrawable.formatted ?? "--") }

    func validate(wallet: DeviceWalletSummary, now: Date, continuousNow: ContinuousClock.Instant = .now) throws {
        try intent.validate(wallet: wallet)
        try fee.validate(now: now, continuousNow: continuousNow)
        let capacity = HyperliquidWithdrawalAvailability(balance: balance, flatAccount: flatAccount)
        guard intent.source == capacity.source else { throw HyperliquidWithdrawalError.unsupportedBalance }
        let available = try capacity.availableUnits(wallet: wallet, now: now)
        guard try intent.amountUnits.multiplied(by: FundingQuantity(100)) <= available else {
            throw HyperliquidWithdrawalError.insufficientBalance
        }
        guard intent.amountUnits > fee.maximumCCTPFee else { throw HyperliquidWithdrawalError.belowFee }
        let age = now.timeIntervalSince1970 * 1000 - Double(intent.nonce)
        guard age.isFinite, age >= -1000, age < 60_000 else { throw HyperliquidWithdrawalError.stale }
    }
}

protocol HyperliquidWithdrawalPreparing: Sendable {
    func availability(wallet: DeviceWalletSummary) async throws -> HyperliquidWithdrawalAvailability
    func source(wallet: DeviceWalletSummary) async throws -> HyperliquidWithdrawalIntent.Source
    func preview(intent: HyperliquidWithdrawalIntent, wallet: DeviceWalletSummary) async throws -> HyperliquidWithdrawalPreview
}

extension HyperliquidWithdrawalPreparing {
    func source(wallet: DeviceWalletSummary) async throws -> HyperliquidWithdrawalIntent.Source { .perps }
}

struct HyperliquidWithdrawalProvider: HyperliquidWithdrawalPreparing {
    var balances: any HyperCoreBalanceProviding = HyperCoreBalanceProvider()
    var fees: any CCTPWithdrawalFeeReading = CCTPWithdrawalFeeReader()
    var flatCheck = HyperliquidFlatAccountCheck()

    func availability(wallet: DeviceWalletSummary) async throws -> HyperliquidWithdrawalAvailability {
        let initial = try await balances.snapshot(wallet: wallet)
        let flat = initial.mode == .unifiedAccount ? try await flatCheck.check(owner: wallet.address) : nil
        let balance = flat != nil ? try await balances.snapshot(wallet: wallet) : initial
        guard balance.mode == initial.mode else { throw HyperliquidWithdrawalError.stale }
        let capacity = HyperliquidWithdrawalAvailability(balance: balance, flatAccount: flat)
        _ = try capacity.availableUnits(wallet: wallet, now: Date())
        return capacity
    }

    func source(wallet: DeviceWalletSummary) async throws -> HyperliquidWithdrawalIntent.Source {
        let balance = try await balances.snapshot(wallet: wallet)
        guard balance.mode != .portfolioMargin else { throw HyperliquidWithdrawalError.unsupportedBalance }
        return balance.mode == .unifiedAccount ? .spot : .perps
    }

    func preview(intent: HyperliquidWithdrawalIntent, wallet: DeviceWalletSummary) async throws -> HyperliquidWithdrawalPreview {
        let flat = intent.source == .spot ? try await flatCheck.check(owner: wallet.address) : nil
        let balance = try await balances.snapshot(wallet: wallet)
        let fee = try await fees.snapshot()
        let preview = HyperliquidWithdrawalPreview(intent: intent, balance: balance, fee: fee, flatAccount: flat)
        try preview.validate(wallet: wallet, now: Date())
        return preview
    }
}

extension HyperliquidWithdrawalError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidIntent: return "Check the Arbitrum address and USDC amount.".bSmartLocalized
        case .insufficientBalance: return "The amount exceeds your withdrawable USDC balance.".bSmartLocalized
        case .unsupportedBalance: return "For unified USDC, close all positions and orders first. Portfolio margin is not supported yet.".bSmartLocalized
        case .belowFee: return "The withdrawal amount must exceed the cross-chain fee.".bSmartLocalized
        case .stale, .routeChanged: return "Withdrawal details changed or expired. Review again.".bSmartLocalized
        case .unavailable: return "Withdrawals are not available yet.".bSmartLocalized
        case .recoveryRequired: return "Withdrawal status is pending verification. Do not send it again.".bSmartLocalized
        case .invalidSignature, .invalidResponse: return "The withdrawal could not be verified.".bSmartLocalized
        }
    }
}
