import Foundation

// A fixed, idempotent account setting. This cannot encode transfers, orders or fee approvals.
struct UnifiedAccountSetup: Codable, Equatable, Sendable {
    let id: UUID
    let accountID: UUID
    let owner: String
    let nonce: UInt64
    let createdAt: Date

    var wallet: DeviceWalletSummary { .init(accountID: accountID, address: owner, recoveryVerified: true) }

    func validate(wallet: DeviceWalletSummary, now: Date? = nil) throws {
        guard wallet.canAuthorizeTransactions, wallet.accountID == accountID, wallet.address == owner,
              TradingWalletChallenge.validAddress(owner), owner == owner.lowercased(),
              owner != "0x" + String(repeating: "0", count: 40), nonce > 0, nonce < 9_007_199_254_680_991,
              createdAt.timeIntervalSince1970.isFinite,
              abs(Double(nonce) - createdAt.timeIntervalSince1970 * 1000) <= 1000 else {
            throw HyperliquidTradingCheckError.accountChanged
        }
        if let now {
            let age = now.timeIntervalSince(createdAt)
            guard age >= 0, age < 60 else { throw HyperliquidTradingCheckError.stale }
        }
    }
}

final class UnifiedAccountSetupPermit: @unchecked Sendable {
    let setup: UnifiedAccountSetup
    private let lock = NSLock()
    private var signed = false
    private var submitted = false
    fileprivate init(_ setup: UnifiedAccountSetup) { self.setup = setup }

    func consumeSigning(wallet: DeviceWalletSummary, now: Date) throws {
        lock.lock(); defer { lock.unlock() }
        guard !signed else { throw FundingJournalError.invalidTransition }
        try setup.validate(wallet: wallet, now: now)
        signed = true
    }

    func start<T>(signature: String, lease: FundingSigningLease, _ operation: (Data) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard signed, !submitted else { throw FundingJournalError.invalidTransition }
        try setup.validate(wallet: lease.wallet, now: Date())
        let body = try UnifiedAccountSetupCodec.envelope(setup, signature: signature)
        submitted = true
        return try lease.perform(wallet: lease.wallet) { try operation(body) }
    }
}

extension FundingTransactionJournal {
    func reserveUnifiedAccountSetup(wallet: DeviceWalletSummary) throws -> UnifiedAccountSetupPermit {
        try locked { anchor, database, snapshot in
            let now = clock(), ms = now.timeIntervalSince1970 * 1000
            guard ms.isFinite, ms > 0, ms < 9_007_199_254_680_991 else { throw FundingJournalError.expired }
            let latest = snapshot.latestHyperliquidNonce(owner: wallet.address)
            guard latest < UInt64(ms) + 1000 else { throw FundingJournalError.conflict }
            let record = UnifiedAccountSetup(id: UUID(), accountID: wallet.accountID, owner: wallet.address,
                nonce: max(UInt64(ms), latest + 1), createdAt: now)
            try record.validate(wallet: wallet, now: now)
            try snapshot.checkHyperliquidReservation(id: record.id, owner: record.owner, nonce: record.nonce, at: now)
            try appendEvent(.accountSetup(record), anchor: &anchor, database: database, records: &snapshot)
            return UnifiedAccountSetupPermit(record)
        }
    }
}
