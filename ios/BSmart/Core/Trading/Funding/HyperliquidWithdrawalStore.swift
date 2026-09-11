import Foundation
import Combine

@MainActor
final class HyperliquidWithdrawalStore: ObservableObject {
    @Published private(set) var preview: HyperliquidWithdrawalPreview?
    @Published private(set) var result: HyperliquidWithdrawalRecord?
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    private let service: any AccountWalletServicing
    private let journal: FundingTransactionJournal
    private let provider: any HyperliquidWithdrawalPreparing
    private let signer: any HyperliquidWithdrawalSigning
    private let broadcaster: any HyperliquidWithdrawalBroadcasting
    private let enabled: () -> Bool
    private let clock: @Sendable () -> Date
    private let continuousClock: @Sendable () -> ContinuousClock.Instant
    private var revision = UUID()
    private var lease: FundingSigningLease?

    init(service: any AccountWalletServicing, journal: FundingTransactionJournal,
         provider: any HyperliquidWithdrawalPreparing = HyperliquidWithdrawalProvider(),
         signer: any HyperliquidWithdrawalSigning = KeychainDeviceWalletVault(),
         broadcaster: any HyperliquidWithdrawalBroadcasting = HyperliquidOrderBroadcaster(),
         clock: @escaping @Sendable () -> Date = { Date() },
         continuousClock: @escaping @Sendable () -> ContinuousClock.Instant = { .now }, enabled: @escaping () -> Bool) {
        self.service = service; self.journal = journal; self.provider = provider; self.signer = signer
        self.broadcaster = broadcaster; self.enabled = enabled; self.clock = clock; self.continuousClock = continuousClock
    }

    func invalidate() {
        revision = UUID(); lease?.invalidate(); lease = nil; preview = nil
    }

    func review(amount: String, recipient: String, wallet: DeviceWalletSummary) async {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil; preview = nil; result = nil
        let token = revision
        defer { isBusy = false }
        do {
            try await verify(wallet: wallet, token: token)
            let records = try await journal.withdrawalRecords(wallet: wallet)
            if let pending = records.first(where: { $0.blocksNewAction(at: clock()) }) {
                if token == revision { result = pending }
                throw HyperliquidWithdrawalError.recoveryRequired
            }
            let source = try await provider.source(wallet: wallet)
            let nonce = try await journal.nextHyperliquidNonce(wallet: wallet)
            let intent = try HyperliquidWithdrawalIntent(wallet: wallet, recipient: recipient, amount: amount, source: source, nonce: nonce)
            let reviewed = try await provider.preview(intent: intent, wallet: wallet)
            try checked(reviewed, wallet: wallet, token: token)
            preview = reviewed
        } catch { if token == revision { errorMessage = message(error) } }
    }

    func confirm(wallet: DeviceWalletSummary) async {
        guard !isBusy, let reviewed = preview else { return }
        isBusy = true; errorMessage = nil
        let token = revision, id = UUID()
        var reserved = false
        defer { lease?.invalidate(); lease = nil; isBusy = false }
        do {
            try checked(reviewed, wallet: wallet, token: token)
            try await verify(wallet: wallet, token: token)
            let refreshed = try await refresh(reviewed, wallet: wallet)
            let nonce = try await journal.nextHyperliquidNonce(wallet: wallet)
            let intent = try HyperliquidWithdrawalIntent(wallet: wallet, recipient: reviewed.intent.recipient,
                amount: reviewed.intent.amount.wire, source: reviewed.intent.source, nonce: nonce)
            let fresh = HyperliquidWithdrawalPreview(intent: intent, balance: refreshed.balance, fee: refreshed.fee, flatAccount: refreshed.flatAccount)
            try checked(fresh, wallet: wallet, token: token)
            _ = try await journal.reserveWithdrawal(id: id, intent: fresh.intent, wallet: wallet)
            reserved = true; preview = nil
            let scope = try service.fundingSigningLease(wallet: wallet)
            lease = scope
            try checked(fresh, wallet: wallet, token: token)
            let permit = try await journal.beginWithdrawalSigning(id: id, preview: fresh, wallet: wallet, continuousNow: continuousClock())
            let signature = try await signer.signWithdrawal(permit, lease: scope)
            // Keep the signature/response even when the presenting screen disappears.
            _ = try await journal.recordWithdrawalSignature(id: id, signature: signature, wallet: wallet)
            try await verify(wallet: wallet, token: token)
            let submission = try await refresh(fresh, wallet: wallet)
            try checked(submission, wallet: wallet, token: token)
            try scope.check(wallet: wallet)
            let send = try await journal.beginWithdrawalSubmission(id: id, preview: submission, wallet: wallet,
                                                                  continuousClock: continuousClock)
            let response: Data?
            do { response = try await broadcaster.submit(send, lease: scope) }
            catch { response = nil }
            let recorded = try await journal.recordWithdrawalResponse(id: id, response: response, wallet: wallet)
            if token == revision, service.walletAccountID == wallet.accountID { result = recorded }
        } catch {
            if token == revision { errorMessage = reserved ? HyperliquidWithdrawalError.recoveryRequired.localizedDescription : message(error) }
        }
    }

    private func refresh(_ reviewed: HyperliquidWithdrawalPreview, wallet: DeviceWalletSummary) async throws -> HyperliquidWithdrawalPreview {
        let fresh = try await provider.preview(intent: reviewed.intent, wallet: wallet)
        guard fresh.intent == reviewed.intent, fresh.balance.mode == reviewed.balance.mode,
              fresh.fee.maximumCCTPFee <= reviewed.fee.maximumCCTPFee,
              fresh.fee.contractCodeHash == reviewed.fee.contractCodeHash else { throw HyperliquidWithdrawalError.stale }
        return fresh
    }

    private func verify(wallet: DeviceWalletSummary, token: UUID) async throws {
        try check(wallet: wallet, token: token)
        let registration = try await service.walletRegistration()
        try check(wallet: wallet, token: token)
        guard registration.accountId == wallet.accountID, registration.address == wallet.address else { throw DeviceWalletError.accountChanged }
    }

    private func check(wallet: DeviceWalletSummary, token: UUID) throws {
        try Task.checkCancellation()
        guard enabled() else { throw HyperliquidWithdrawalError.unavailable }
        guard token == revision, wallet.canAuthorizeTransactions, service.walletAccountID == wallet.accountID else { throw DeviceWalletError.accountChanged }
    }

    private func checked(_ preview: HyperliquidWithdrawalPreview, wallet: DeviceWalletSummary, token: UUID) throws {
        try check(wallet: wallet, token: token)
        try preview.validate(wallet: wallet, now: clock(), continuousNow: continuousClock())
    }

    private func message(_ error: Error) -> String {
        if let error = error as? HyperliquidWithdrawalError { return error.localizedDescription }
        if let error = error as? DeviceWalletError { return error.localizedDescription }
        if let error = error as? HyperCoreBalanceError { return error.localizedDescription }
        if let error = error as? HyperliquidFlatAccountError { return error.localizedDescription }
        if error is FundingJournalError { return HyperliquidWithdrawalError.recoveryRequired.localizedDescription }
        return HyperliquidWithdrawalError.invalidIntent.localizedDescription
    }
}
