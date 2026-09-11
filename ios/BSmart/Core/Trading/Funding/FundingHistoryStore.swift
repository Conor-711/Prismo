import Foundation
import Combine

@MainActor
final class FundingHistoryStore: ObservableObject {
    @Published private(set) var entries: [FundingHistoryEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var didLoad = false
    @Published private(set) var errorMessage: String?
    private let service: AccountWalletServicing
    private let journal: FundingHistoryAccessing
    private let observer: FundingSourceObserving
    private let attester: CCTPAttestationObserving
    private let forwarder: CCTPForwardObserving
    private var revision = UUID()

    init(service: AccountWalletServicing, journal: FundingHistoryAccessing,
         observer: FundingSourceObserving = ArbitrumSourceObserver(),
         attester: CCTPAttestationObserving = CCTPAttestationObserver(),
         forwarder: CCTPForwardObserving = CCTPForwardObserver()) {
        self.service = service
        self.journal = journal
        self.observer = observer
        self.attester = attester
        self.forwarder = forwarder
    }

    func clear() {
        revision = UUID()
        entries = []
        errorMessage = nil
        isLoading = false
        didLoad = false
    }

    func refresh(wallet: DeviceWalletSummary) async {
        await run(wallet: wallet, action: .refresh)
    }

    func cancelReview(id: UUID, wallet: DeviceWalletSummary) async {
        guard !isLoading, entries.contains(where: { $0.id == id && $0.stage.canCancelReview }) else { return }
        await run(wallet: wallet, action: .cancel(id))
    }

    func checkSource(id: UUID, wallet: DeviceWalletSummary) async {
        guard !isLoading, entries.contains(where: { $0.id == id && $0.transactionHash != nil }) else { return }
        await run(wallet: wallet, action: .observe(id))
    }

    func checkCrossChain(id: UUID, wallet: DeviceWalletSummary) async {
        guard !isLoading, entries.contains(where: { $0.id == id && $0.transactionHash != nil }) else { return }
        await run(wallet: wallet, action: .crossChain(id))
    }

    private enum Action { case refresh, cancel(UUID), observe(UUID), crossChain(UUID) }

    private func run(wallet: DeviceWalletSummary, action: Action) async {
        let operation = UUID()
        revision = operation
        isLoading = true
        didLoad = false
        entries = []
        errorMessage = nil
        defer { if revision == operation { isLoading = false } }
        do {
            try check(wallet: wallet, operation: operation)
            let registered = try await service.walletRegistration()
            try check(wallet: wallet, operation: operation)
            guard registered.accountId == wallet.accountID, registered.address == wallet.address else {
                throw FundingJournalError.conflict
            }
            switch action {
            case .refresh: break
            case .cancel(let id):
                try await journal.cancelReview(id: id, wallet: wallet)
                try check(wallet: wallet, operation: operation)
            case .observe(let id), .crossChain(let id):
                guard let sourceJournal = journal as? FundingSourceJournalAccessing else { throw FundingJournalError.unavailable }
                let lookup = try await sourceJournal.sourceLookup(id: id, wallet: wallet)
                try check(wallet: wallet, operation: operation)
                let observation = try await observer.observe(lookup, wallet: wallet)
                // Persist verified evidence even if the screen/account left while the read completed.
                // This grants no signing authority; the journal rechecks the original owner and history.
                try await sourceJournal.recordSourceObservation(observation, wallet: wallet)
                try check(wallet: wallet, operation: operation)
                if case .crossChain = action, observation.receipt?.succeeded == true {
                    guard let crossJournal = journal as? CCTPAttestationJournalAccessing else { throw FundingJournalError.unavailable }
                    let current = try await crossJournal.attestationLookup(id: id, wallet: wallet)
                    try check(wallet: wallet, operation: operation)
                    guard current.source.id == observation.id else { throw FundingJournalError.conflict }
                    let evidence = try await attester.observe(current, wallet: wallet)
                    try await crossJournal.recordAttestation(evidence, wallet: wallet)
                    try check(wallet: wallet, operation: operation)
                    if evidence.proof != nil, evidence.forwardHash != nil {
                        guard let forwardJournal = journal as? CCTPForwardJournalAccessing else { throw FundingJournalError.unavailable }
                        let latest = try await forwardJournal.forwardingLookup(id: id, wallet: wallet)
                        try check(wallet: wallet, operation: operation)
                        guard latest.attestation.id == evidence.id else { throw FundingJournalError.conflict }
                        let forwarded = try await forwarder.observe(latest, wallet: wallet)
                        try await forwardJournal.recordForwarding(forwarded, wallet: wallet)
                        try check(wallet: wallet, operation: operation)
                    }
                }
            }
            let result = try await journal.history(wallet: wallet)
            try check(wallet: wallet, operation: operation)
            guard result.allSatisfy({ $0.accountID == wallet.accountID && $0.owner == wallet.address }),
                  Set(result.map(\.id)).count == result.count else { throw FundingJournalError.integrity }
            entries = result
            didLoad = true
        } catch {
            guard revision == operation else { return }
            if error is CancellationError { return }
            if case .crossChain = action {
                errorMessage = "Cross-chain status could not be verified. Do not send another deposit.".bSmartLocalized
            } else if case .observe = action {
                errorMessage = (error as? FundingObservationError ?? .unavailable).errorDescription
            } else { errorMessage = (error as? FundingJournalError ?? .unavailable).errorDescription }
        }
    }

    private func check(wallet: DeviceWalletSummary, operation: UUID) throws {
        try Task.checkCancellation()
        guard operation == revision, service.walletAccountID == wallet.accountID,
              TradingWalletChallenge.validAddress(wallet.address) else { throw FundingJournalError.conflict }
    }
}
