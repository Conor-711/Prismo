import Foundation
import Combine

struct ArbitrumReceiveContext: Equatable {
    let wallet: DeviceWalletSummary?
    let depositsEnabled: Bool
    let networkConfirmed: Bool

    var eligible: Bool {
        depositsEnabled && networkConfirmed && wallet?.canAuthorizeTransactions == true
    }
}

@MainActor
final class ArbitrumReceiveStore: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var hasChecked = false
    @Published private(set) var errorMessage: String?
    private let service: AccountWalletServicing
    private let now: () -> Date
    private let continuousNow: () -> ContinuousClock.Instant
    private var verified: (context: ArbitrumReceiveContext, address: WalletReceiveAddress,
                           date: Date, instant: ContinuousClock.Instant)?
    private var revision = UUID()

    init(service: AccountWalletServicing, now: @escaping () -> Date = Date.init,
         continuousNow: @escaping () -> ContinuousClock.Instant = { .now }) {
        self.service = service; self.now = now; self.continuousNow = continuousNow
    }

    func refresh(context: ArbitrumReceiveContext) async {
        clear()
        guard context.eligible, let wallet = context.wallet,
              service.walletAccountID == wallet.accountID else { return }
        let operation = revision
        let start = now(), instant = continuousNow()
        isLoading = true
        defer { if revision == operation { isLoading = false } }
        do {
            try Task.checkCancellation()
            let address = try WalletReceiveAddress(owner: wallet.address)
            let registration = try await service.walletRegistration()
            try Task.checkCancellation()
            guard operation == revision else { return }
            guard service.walletAccountID == wallet.accountID,
                  registration.accountId == wallet.accountID, registration.address == wallet.address,
                  isFresh(date: start, instant: instant) else { throw DeviceWalletError.invalidProof }
            verified = (context, address, start, instant)
            hasChecked = true
        } catch {
            guard operation == revision, !Task.isCancelled else { return }
            errorMessage = "Receiving address could not be verified. Try again.".bSmartLocalized
        }
    }

    func currentAddress(context: ArbitrumReceiveContext) -> WalletReceiveAddress? {
        guard context.eligible, let wallet = context.wallet,
              service.walletAccountID == wallet.accountID, let verified,
              verified.context == context, isFresh(date: verified.date, instant: verified.instant) else { return nil }
        return verified.address
    }

    func clear() {
        revision = UUID(); verified = nil; hasChecked = false; isLoading = false; errorMessage = nil
    }

    private func isFresh(date: Date, instant: ContinuousClock.Instant) -> Bool {
        let age = now().timeIntervalSince(date)
        let elapsed = instant.duration(to: continuousNow())
        return age >= 0 && age < 60 && elapsed >= .zero && elapsed < .seconds(60)
    }
}
