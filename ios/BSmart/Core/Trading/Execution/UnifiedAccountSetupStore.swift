import Foundation
import Combine

@MainActor
final class UnifiedAccountSetupStore: ObservableObject {
    @Published private(set) var mode: HyperCoreAccountMode?
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    private let service: any AccountWalletServicing
    private let reader: any HyperliquidExecutionReading
    private let signer: any UnifiedAccountSetupSigning
    private let sender: any UnifiedAccountSetupBroadcasting
    private let journal: FundingTransactionJournal
    private let enabled: () -> Bool
    private var revision = UUID()
    private var lease: FundingSigningLease?
    private var attemptedAutomaticSetup = false

    init(service: any AccountWalletServicing, journal: FundingTransactionJournal,
         reader: any HyperliquidExecutionReading = HyperliquidExecutionReader(),
         signer: any UnifiedAccountSetupSigning = KeychainDeviceWalletVault(),
         sender: any UnifiedAccountSetupBroadcasting = HyperliquidOrderBroadcaster(), enabled: @escaping () -> Bool) {
        self.service = service; self.journal = journal; self.reader = reader
        self.signer = signer; self.sender = sender; self.enabled = enabled
    }

    func invalidate() { revision = UUID(); lease?.invalidate(); lease = nil; mode = nil }

    func prepare(wallet: DeviceWalletSummary) async {
        await refresh(wallet: wallet)
        guard !Task.isCancelled, !attemptedAutomaticSetup, let mode, !mode.usesSharedBalance else { return }
        attemptedAutomaticSetup = true
        await enable(wallet: wallet)
    }

    func refresh(wallet: DeviceWalletSummary) async {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil; mode = nil
        let token = revision
        defer { isBusy = false }
        do {
            try await verify(wallet: wallet, token: token)
            let fetched = try await readMode(wallet)
            try check(wallet, token: token)
            mode = fetched
        } catch { if token == revision { errorMessage = errorText(error) } }
    }

    func enable(wallet: DeviceWalletSummary) async {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil
        let token = revision
        defer { isBusy = false; lease?.invalidate(); lease = nil }
        do {
            try await verify(wallet: wallet, token: token)
            guard enabled() else { throw HyperliquidWithdrawalError.unavailable }
            let current = try await readMode(wallet)
            if current == .unifiedAccount { mode = current; return }
            guard current != .portfolioMargin else { throw HyperliquidFlatAccountError.hasExposure }
            _ = try await HyperliquidFlatAccountCheck(reader: reader).check(owner: wallet.address)
            try check(wallet, token: token)
            let permit = try await journal.reserveUnifiedAccountSetup(wallet: wallet)
            let scope = try service.fundingSigningLease(wallet: wallet); lease = scope
            let signature = try await signer.signUnifiedAccount(permit, lease: scope)
            try await verify(wallet: wallet, token: token)
            guard enabled(), try await readMode(wallet) == current else { throw HyperliquidTradingCheckError.stale }
            let flat = try await HyperliquidFlatAccountCheck(reader: reader).check(owner: wallet.address)
            try flat.validate(owner: wallet.address, now: Date())
            try check(wallet, token: token)
            let response = try await sender.submit(permit, signature: signature, lease: scope)
            try check(wallet, token: token)
            // Even an uncertain write is resolved by reading the authoritative mode, never by resending.
            let actual = try await readMode(wallet)
            try check(wallet, token: token)
            mode = actual
            if actual != .unifiedAccount {
                if let response, case .rejected(let reason) = try? HyperliquidWithdrawalAcknowledgement.decode(response) {
                    errorMessage = reason
                } else {
                    errorMessage = "Account setup is not confirmed. Refresh to check again.".bSmartLocalized
                }
            }
        } catch { if token == revision { errorMessage = errorText(error) } }
    }

    private func readMode(_ wallet: DeviceWalletSummary) async throws -> HyperCoreAccountMode {
        let raw = try JSONDecoder().decode(String.self, from: await reader.read(.mode(owner: wallet.address)))
        guard let mode = HyperCoreAccountMode(rawValue: raw) else { throw HyperliquidTradingCheckError.invalidResponse }
        return mode
    }

    private func verify(wallet: DeviceWalletSummary, token: UUID) async throws {
        try check(wallet, token: token)
        let registered = try await service.walletRegistration()
        try check(wallet, token: token)
        guard registered.accountId == wallet.accountID, registered.address == wallet.address else { throw DeviceWalletError.accountChanged }
    }

    private func check(_ wallet: DeviceWalletSummary, token: UUID) throws {
        try Task.checkCancellation()
        guard revision == token, wallet.canAuthorizeTransactions, service.walletAccountID == wallet.accountID else { throw DeviceWalletError.accountChanged }
    }

    private func errorText(_ error: Error) -> String {
        if let error = error as? HyperliquidFlatAccountError { return error.localizedDescription }
        if let error = error as? DeviceWalletError { return error.localizedDescription }
        return "Account setup is not confirmed. Refresh to check again.".bSmartLocalized
    }
}
