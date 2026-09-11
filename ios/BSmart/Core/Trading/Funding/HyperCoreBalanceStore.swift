import Foundation
import Combine

@MainActor
final class HyperCoreBalanceStore: ObservableObject {
    @Published private(set) var snapshot: HyperCoreBalanceSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private let service: AccountWalletServicing
    private let provider: HyperCoreBalanceProviding
    private let clock: () -> Date
    private var revision = UUID()

    init(service: AccountWalletServicing, provider: HyperCoreBalanceProviding = HyperCoreBalanceProvider(),
         clock: @escaping () -> Date = Date.init) {
        self.service = service; self.provider = provider; self.clock = clock
    }

    func refresh(wallet: DeviceWalletSummary) async {
        let operation = UUID()
        revision = operation; snapshot = nil; errorMessage = nil; isLoading = true
        defer { if revision == operation { isLoading = false } }
        do {
            try check(wallet, operation)
            let registered = try await service.walletRegistration()
            try check(wallet, operation)
            guard registered.accountId == wallet.accountID, registered.address == wallet.address else {
                throw HyperCoreBalanceError.accountChanged
            }
            let result = try await provider.snapshot(wallet: wallet)
            try check(wallet, operation)
            try result.validate(wallet: wallet, now: clock())
            snapshot = result
        } catch {
            guard revision == operation, !Task.isCancelled else { return }
            errorMessage = (error as? HyperCoreBalanceError ?? .unavailable).errorDescription
        }
    }

    func clear() {
        revision = UUID(); snapshot = nil; isLoading = false; errorMessage = nil
    }

    func currentSnapshot(wallet: DeviceWalletSummary, now: Date) -> HyperCoreBalanceSnapshot? {
        guard service.walletAccountID == wallet.accountID, let snapshot,
              (try? snapshot.validate(wallet: wallet, now: now)) != nil else { return nil }
        return snapshot
    }

    private func check(_ wallet: DeviceWalletSummary, _ operation: UUID) throws {
        try Task.checkCancellation()
        guard revision == operation, service.walletAccountID == wallet.accountID,
              TradingWalletChallenge.validAddress(wallet.address) else { throw HyperCoreBalanceError.accountChanged }
    }
}
