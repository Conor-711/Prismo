import Foundation
import Combine

@MainActor
final class ManagedFundingStore: ObservableObject {
    @Published private(set) var available = false
    @Published private(set) var isLoading = false
    @Published private(set) var isCheckingAvailability = false
    @Published private(set) var address: ManagedFundingAddress?
    @Published private(set) var deposits: [ManagedFundingDeposit] = []
    @Published private var availabilityError: String?
    @Published private var addressError: String?
    var errorMessage: String? { availabilityError ?? addressError }
    @Published private(set) var historyError: String?
    private let service: ManagedFundingServicing
    private var revision = UUID()
    private var addressRevision = UUID()

    init(service: ManagedFundingServicing) { self.service = service }

    func load(wallet: DeviceWalletSummary) async {
        clear()
        let operation = revision
        isCheckingAvailability = true
        defer { if revision == operation { isCheckingAvailability = false } }
        do {
            let result = try await service.available(wallet: wallet)
            guard current(operation, wallet) else { return }
            available = result
            if !result { availabilityError = ManagedFundingError.unavailable.localizedDescription }
        } catch {
            guard current(operation, wallet) else { return }
            availabilityError = ManagedFundingError.unavailable.localizedDescription
        }
    }

    func prepare(wallet: DeviceWalletSummary, network: ManagedFundingNetwork) async {
        guard available, !isLoading else { return }
        invalidateAddress()
        let operation = revision
        let addressOperation = addressRevision
        isLoading = true
        defer { if revision == operation && addressRevision == addressOperation { isLoading = false } }
        do {
            let result = try await service.address(wallet: wallet, network: network)
            guard current(operation, wallet), addressRevision == addressOperation else { return }
            try result.validate(owner: wallet.address, network: network)
            address = result
        } catch {
            guard current(operation, wallet), addressRevision == addressOperation else { return }
            addressError = ManagedFundingError.unavailable.localizedDescription
        }
    }

    func refreshHistory(wallet: DeviceWalletSummary) async {
        let operation = revision
        do {
            let result = try await service.deposits(wallet: wallet)
            guard current(operation, wallet) else { return }
            deposits = result; historyError = nil
        } catch {
            guard current(operation, wallet) else { return }
            historyError = "Deposit history could not be refreshed.".bSmartLocalized
        }
    }

    func invalidateAddress() {
        // A network change invalidates its address, not the account's availability check.
        addressRevision = UUID(); address = nil; isLoading = false; addressError = nil
    }

    func clear() {
        revision = UUID()
        invalidateAddress(); available = false; isCheckingAvailability = false
        availabilityError = nil; deposits = []; historyError = nil
    }

    private func current(_ operation: UUID, _ wallet: DeviceWalletSummary) -> Bool {
        !Task.isCancelled && revision == operation && service.accountID == wallet.accountID
    }
}
