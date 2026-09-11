import Foundation

final class HyperliquidWithdrawalSigningPermit: @unchecked Sendable {
    let preview: HyperliquidWithdrawalPreview
    private let lock = NSLock()
    private var consumed = false
    fileprivate init(preview: HyperliquidWithdrawalPreview) { self.preview = preview }

    func consume(wallet: DeviceWalletSummary, now: Date, continuousNow: ContinuousClock.Instant = .now) throws {
        lock.lock(); defer { lock.unlock() }
        guard !consumed else { throw FundingJournalError.invalidTransition }
        consumed = true
        try preview.validate(wallet: wallet, now: now, continuousNow: continuousNow)
    }
}

final class HyperliquidWithdrawalSubmissionPermit: @unchecked Sendable {
    private let preview: HyperliquidWithdrawalPreview
    private let body: Data
    private let wallet: DeviceWalletSummary
    private let clock: @Sendable () -> Date
    private let continuousClock: @Sendable () -> ContinuousClock.Instant
    private let lock = NSLock()
    private var consumed = false

    fileprivate init(preview: HyperliquidWithdrawalPreview, body: Data, wallet: DeviceWalletSummary,
                     clock: @escaping @Sendable () -> Date, continuousClock: @escaping @Sendable () -> ContinuousClock.Instant) {
        self.preview = preview; self.body = body; self.wallet = wallet
        self.clock = clock; self.continuousClock = continuousClock
    }

    func start<T>(lease: FundingSigningLease, _ operation: (Data) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard !consumed else { throw FundingJournalError.invalidTransition }
        consumed = true
        return try lease.perform(wallet: wallet) {
            try preview.validate(wallet: wallet, now: clock(), continuousNow: continuousClock())
            return try operation(body)
        }
    }
}

extension FundingTransactionJournal {
    func beginWithdrawalSigning(id: UUID, preview: HyperliquidWithdrawalPreview, wallet: DeviceWalletSummary,
                                continuousNow: ContinuousClock.Instant = .now) throws -> HyperliquidWithdrawalSigningPermit {
        try preview.validate(wallet: wallet, now: clock(), continuousNow: continuousNow)
        _ = try recordWithdrawalSigningStarted(id: id, intent: preview.intent, wallet: wallet)
        return .init(preview: preview)
    }

    func beginWithdrawalSubmission(id: UUID, preview: HyperliquidWithdrawalPreview, wallet: DeviceWalletSummary,
        continuousClock: @escaping @Sendable () -> ContinuousClock.Instant = { .now }) throws -> HyperliquidWithdrawalSubmissionPermit {
        try preview.validate(wallet: wallet, now: clock(), continuousNow: continuousClock())
        let record = try recordWithdrawalSubmissionStarted(id: id, intent: preview.intent, wallet: wallet)
        guard let signature = record.signature else { throw FundingJournalError.integrity }
        let body = try HyperliquidWithdrawalCodec.envelope(preview.intent, signature: signature)
        return .init(preview: preview, body: body, wallet: wallet, clock: clock, continuousClock: continuousClock)
    }
}
