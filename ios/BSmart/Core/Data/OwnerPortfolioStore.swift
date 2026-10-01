import Foundation
import Combine

@MainActor
final class OwnerPortfolioStore: ObservableObject {
    @Published private(set) var accountID: UUID?
    @Published private(set) var portfolio: FeedPublicPortfolio?
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    private var requestID = UUID()
    private var loadTask: Task<FeedPublicPortfolio, Error>?
    private var loadedAt: Date?
    private let fetch: (AccountAccessStore, UUID) async throws -> FeedPublicPortfolio
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init,
         fetch: @escaping (AccountAccessStore, UUID) async throws -> FeedPublicPortfolio = {
             try await NativeTradeFeedClient(account: $0).ownPortfolio(accountID: $1)
         }) {
        self.now = now
        self.fetch = fetch
    }

    var hasUnavailableAccountValue: Bool {
        guard let portfolio, portfolio.status == .ready else { return false }
        guard let raw = portfolio.accountValueUSD, let value = Double(raw) else { return true }
        return !value.isFinite
    }

    func clear() {
        loadTask?.cancel()
        loadTask = nil
        loadedAt = nil
        requestID = UUID()
        accountID = nil
        portfolio = nil
        isLoading = false
        failed = false
    }

    func load(account: AccountAccessStore, force: Bool = false) async {
        guard let id = account.identity?.id else { clear(); return }
        if accountID != id {
            clear()
            accountID = id
        }
        if let loadTask { _ = await loadTask.result; return }
        guard force || portfolio == nil || loadedAt.map({ now().timeIntervalSince($0) >= 30 }) != false else { return }
        let request = UUID()
        requestID = request
        isLoading = true
        failed = false
        // A tab change must not cancel a read shared by the next visit.
        let task = Task { try await fetch(account, id) }
        loadTask = task
        defer { if requestID == request { isLoading = false; loadTask = nil } }
        do {
            let result = try await task.value
            guard requestID == request, account.identity?.id == id else { return }
            try result.validate()
            portfolio = result
            loadedAt = now()
        } catch {
            guard requestID == request, account.identity?.id == id, !(error is CancellationError) else { return }
            failed = true
        }
    }
}
