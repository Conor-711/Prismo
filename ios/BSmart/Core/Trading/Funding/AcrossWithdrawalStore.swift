import Foundation
import Combine

@MainActor
final class AcrossWithdrawalStore: ObservableObject {
    @Published private(set) var quote: AcrossWithdrawalQuote?
    @Published private(set) var history: [AcrossWithdrawalRecord] = []
    @Published private(set) var availableAmount: String?
    @Published private(set) var hasLoaded = false
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?

    private let service: AccountAccessStore
    private let client: AcrossWithdrawalClient
    private let signer: any TradingWalletSigning
    private let provider: any HyperliquidWithdrawalPreparing
    private let enabled: () -> Bool
    private var revision = UUID()

    var pending: AcrossWithdrawalRecord? { history.first(where: \.blocksNewWithdrawal) }

    init(service: AccountAccessStore, signer: any TradingWalletSigning,
         provider: any HyperliquidWithdrawalPreparing = HyperliquidWithdrawalProvider(),
         enabled: @escaping () -> Bool) throws {
        self.service = service
        client = try AcrossWithdrawalClient(account: service)
        self.signer = signer
        self.provider = provider
        self.enabled = enabled
    }

    func invalidate() { revision = UUID(); quote = nil }

    func load(wallet: DeviceWalletSummary) async {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil
        let token = revision
        defer { isBusy = false }
        do {
            try await verify(wallet: wallet, token: token, requireEnabled: false)
            history = try await client.history(wallet: wallet)
            try check(wallet: wallet, token: token, requireEnabled: false)
            guard enabled(), pending == nil else {
                availableAmount = nil
                hasLoaded = pending != nil || service.configuration.acrossWithdrawalsEnabled != true
                return
            }
            let capacity = try await provider.availability(wallet: wallet)
            try check(wallet: wallet, token: token)
            availableAmount = try capacity.maximumAmount(wallet: wallet, now: Date())
            hasLoaded = true
        } catch {
            if token == revision, !(error is CancellationError) { errorMessage = message(error) }
        }
    }

    func review(amount: String, recipient: String, wallet: DeviceWalletSummary) async {
        guard !isBusy, quote == nil else { return }
        isBusy = true; errorMessage = nil
        let token = revision
        defer { isBusy = false }
        do {
            try await verify(wallet: wallet, token: token)
            history = try await client.history(wallet: wallet)
            guard pending == nil else { throw HyperliquidWithdrawalError.recoveryRequired }
            guard let requested = Decimal(string: amount), requested > 0,
                  let availableAmount, let available = Decimal(string: availableAmount), requested <= available,
                  TradingWalletChallenge.validAddress(recipient) else {
                throw HyperliquidWithdrawalError.invalidIntent
            }
            let capacity = try await provider.availability(wallet: wallet)
            guard requested <= Decimal(string: try capacity.maximumAmount(wallet: wallet, now: Date())) ?? 0 else {
                throw HyperliquidWithdrawalError.insufficientBalance
            }
            let source = capacity.source == .spot ? "spot" : "perps"
            let fresh = try await client.quote(id: UUID(), amount: amount, source: source,
                                               recipient: recipient, wallet: wallet)
            try check(wallet: wallet, token: token)
            quote = fresh
        } catch {
            if token == revision { errorMessage = message(error) }
            if token == revision { history = (try? await client.history(wallet: wallet)) ?? history }
        }
    }

    func cancelReview(wallet: DeviceWalletSummary) async {
        guard !isBusy, let quote else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do {
            try await client.cancel(quote, wallet: wallet)
            self.quote = nil
            history = try await client.history(wallet: wallet)
        } catch { errorMessage = message(error) }
    }

    func confirm(wallet: DeviceWalletSummary) async {
        guard !isBusy, let quote else { return }
        isBusy = true; errorMessage = nil
        let token = revision
        defer { isBusy = false }
        do {
            try await verify(wallet: wallet, token: token)
            guard quote.record.quoteExpiresAt.timeIntervalSinceNow > 8 else {
                throw HyperliquidWithdrawalError.stale
            }
            let lease = try service.fundingSigningLease(wallet: wallet)
            defer { lease.invalidate() }
            var signatures: [String: String] = [:]
            for step in quote.steps {
                try lease.check(wallet: wallet)
                signatures[step.stepID] = try await signer.signAcrossStep(step, lease: lease)
            }
            try await verify(wallet: wallet, token: token)
            guard quote.record.quoteExpiresAt.timeIntervalSinceNow > 5 else {
                throw HyperliquidWithdrawalError.stale
            }
            _ = try await client.submit(quote, signatures: signatures, wallet: wallet)
            self.quote = nil
            history = try await client.history(wallet: wallet)
            availableAmount = nil
        } catch {
            if token == revision {
                // A submit timeout is ambiguous. Never submit the signed quote again.
                self.quote = nil
                errorMessage = message(error)
                history = (try? await client.history(wallet: wallet)) ?? history
            }
        }
    }

    private func verify(wallet: DeviceWalletSummary, token: UUID, requireEnabled: Bool = true) async throws {
        try check(wallet: wallet, token: token, requireEnabled: requireEnabled)
        let registration = try await service.walletRegistration()
        try check(wallet: wallet, token: token, requireEnabled: requireEnabled)
        guard registration.accountId == wallet.accountID, registration.address == wallet.address else {
            throw DeviceWalletError.accountChanged
        }
    }

    private func check(wallet: DeviceWalletSummary, token: UUID, requireEnabled: Bool = true) throws {
        try Task.checkCancellation()
        guard !requireEnabled || enabled() else { throw HyperliquidWithdrawalError.unavailable }
        guard token == revision, wallet.canAuthorizeTransactions,
              service.walletAccountID == wallet.accountID else { throw DeviceWalletError.accountChanged }
    }

    private func message(_ error: Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription { return description }
        return "Withdrawal status may be pending. Refresh before trying again.".bSmartLocalized
    }
}
