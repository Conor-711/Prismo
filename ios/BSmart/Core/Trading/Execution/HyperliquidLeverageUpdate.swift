import Foundation

struct HyperliquidLeverageUpdate: Codable, Equatable, Sendable {
    let id: UUID
    let accountID: UUID
    let owner: String
    let market: HyperliquidExecutionMarket
    let leverage: Int
    let isCross: Bool
    let nonce: UInt64
    let createdAt: Date
    var expiresAfter: UInt64 { nonce + 60_000 }
    var wallet: DeviceWalletSummary { .init(accountID: accountID, address: owner, recoveryVerified: true) }

    func validate(wallet: DeviceWalletSummary, now: Date? = nil) throws {
        try market.validatePerpetual()
        guard wallet.canAuthorizeTransactions, wallet.accountID == accountID, wallet.address == owner,
              TradingWalletChallenge.validAddress(owner), owner == owner.lowercased(),
              (1...market.maximumLeverage).contains(leverage), !market.isolatedOnly || !isCross,
              nonce > 0, nonce < 9_007_199_254_680_991, createdAt.timeIntervalSince1970.isFinite,
              abs(Double(nonce) - createdAt.timeIntervalSince1970 * 1000) <= 1000 else {
            throw HyperliquidExecutionError.invalidIntent
        }
        if let now {
            guard now >= createdAt, now.timeIntervalSince1970 * 1000 < Double(expiresAfter) else {
                throw HyperliquidTradingCheckError.stale
            }
        }
    }
}

final class HyperliquidLeveragePermit: @unchecked Sendable {
    let update: HyperliquidLeverageUpdate
    private let lock = NSLock()
    private var signed = false
    private var submitted = false
    fileprivate init(_ update: HyperliquidLeverageUpdate) { self.update = update }

    func consume(wallet: DeviceWalletSummary, now: Date) throws {
        lock.lock(); defer { lock.unlock() }
        guard !signed else { throw FundingJournalError.invalidTransition }
        try update.validate(wallet: wallet, now: now)
        signed = true
    }

    func start<T>(signature: String, lease: FundingSigningLease, _ operation: (Data) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard signed, !submitted else { throw FundingJournalError.invalidTransition }
        try update.validate(wallet: lease.wallet, now: Date())
        let body = try HyperliquidLeverageCodec.envelope(update, signature: signature)
        submitted = true
        return try lease.perform(wallet: lease.wallet) { try operation(body) }
    }
}

extension FundingTransactionJournal {
    func reserveLeverage(wallet: DeviceWalletSummary, market: HyperliquidExecutionMarket,
                         leverage: Int, isCross: Bool) throws -> HyperliquidLeveragePermit {
        try locked { anchor, database, snapshot in
            let now = clock(), ms = now.timeIntervalSince1970 * 1000
            guard ms.isFinite, ms > 0, ms < 9_007_199_254_680_991 else { throw FundingJournalError.expired }
            let latest = snapshot.latestHyperliquidNonce(owner: wallet.address)
            guard latest < UInt64(ms) + 1000 else { throw FundingJournalError.conflict }
            let update = HyperliquidLeverageUpdate(id: UUID(), accountID: wallet.accountID, owner: wallet.address,
                market: market, leverage: leverage, isCross: isCross, nonce: max(UInt64(ms), latest + 1), createdAt: now)
            try update.validate(wallet: wallet, now: now)
            try appendEvent(.leverage(update), anchor: &anchor, database: database, records: &snapshot)
            return HyperliquidLeveragePermit(update)
        }
    }
}
