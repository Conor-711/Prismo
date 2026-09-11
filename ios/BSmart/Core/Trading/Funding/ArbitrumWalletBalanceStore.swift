import Foundation
import Combine

@MainActor
final class ArbitrumWalletBalanceStore: ObservableObject {
    @Published private(set) var snapshot: ArbitrumWalletSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private let provider: ArbitrumWalletSnapshotProviding
    private var revision = UUID()

    init(provider: ArbitrumWalletSnapshotProviding = ArbitrumSourcePreflight()) { self.provider = provider }

    func refresh(wallet: DeviceWalletSummary) async {
        let operation = UUID()
        revision = operation
        snapshot = nil
        errorMessage = nil
        isLoading = true
        defer { if revision == operation { isLoading = false } }
        do {
            let result = try await provider.snapshot(wallet: wallet)
            guard revision == operation, !Task.isCancelled else { return }
            try result.validate(wallet: wallet, now: Date())
            snapshot = result
        } catch {
            guard revision == operation, !Task.isCancelled else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? FundingPreflightError.unavailable.localizedDescription
        }
    }

    func clear() {
        revision = UUID()
        snapshot = nil
        errorMessage = nil
        isLoading = false
    }
}
