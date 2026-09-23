import Foundation

/// Research only. Private portfolio state and authenticated trading have separate owners.
@MainActor
final class SupabaseContentClient: BSmartAPIClient, BSmartContentRefreshing, BSmartDataFreshnessProviding {
    typealias Request = (String, [URLQueryItem]) async throws -> Data
    private let configuration: SupabaseAccountConfiguration?
    private let injectedRequest: Request?
    private weak var account: AccountAccessStore?
    private var transport: SupabaseAccountTransport?
    private var manifest: SupabaseContentManifest?
    private var refreshTask: Task<Void, Error>?
    private var snapshot: Snapshot?
    private nonisolated let freshnessState = SupabaseContentFreshness()

    private struct Snapshot {
        let signals: [PortfolioSignal]
        let updates: [SmartAccountUpdate]
        let accounts: [SmartAccountProfile]
        let intelligence: [TickerIntelligence]
        let money: [SmartMoneySignal]
        let movements: [SmartMoneyMovement]
    }

    init(configuration: SupabaseAccountConfiguration? = nil, request: Request? = nil) {
        self.configuration = configuration
        self.injectedRequest = request
        transport = configuration.map { SupabaseAccountTransport(configuration: $0) }
    }

    func bind(account: AccountAccessStore) { self.account = account }

    nonisolated var latestDataAsOf: Date? { freshnessState.latest }
    nonisolated func freshness(for source: BSmartLiveDataSource) -> BSmartDataFreshness? { freshnessState.value(for: source) }

    func prepareContentRefresh() async throws {
        if let refreshTask { return try await refreshTask.value }
        let task = Task { try await stageSnapshot() }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    private func request(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        try Task.checkCancellation()
        if let injectedRequest { return try await injectedRequest(path, query) }
        guard let account, let transport else { throw AccountAccessError.unavailable }
        return try await account.withFeedSession { token in
            try await transport.request("functions/v1/bsmart-content/" + path, query: query, token: token)
        }
    }

    private func stageSnapshot() async throws {
        let data = try await request("manifest")
        let incoming = try BSmartJSONCoding.makeDecoder().decode(SupabaseContentManifest.self, from: data)
        try incoming.validate()
        if incoming == manifest { return }
        // Keep the current UI intact until every required collection has decoded.
        let signals: [PortfolioSignal] = try await collection("portfolio-signals", in: incoming, previous: snapshot?.signals)
        let updates: [SmartAccountUpdate] = try await collection("smart-account-updates", in: incoming, previous: snapshot?.updates)
        let accounts: [SmartAccountProfile] = try await collection("smart-accounts", in: incoming, previous: snapshot?.accounts)
        let intelligence: [TickerIntelligence] = try await collection("ticker-intelligence", in: incoming, previous: snapshot?.intelligence)
        let money: [SmartMoneySignal] = try await collection("smart-money", in: incoming, previous: snapshot?.money)
        let movements: [SmartMoneyMovement] = try await collection("smart-money-movements", in: incoming, previous: snapshot?.movements)
        if !money.isEmpty { try HTTPBSmartAPIClient.validateSmartMoney(money) }
        let authorIDs = Set(accounts.map(\.id))
        guard !accounts.isEmpty, authorIDs.count == accounts.count,
              updates.allSatisfy({ authorIDs.contains($0.authorId) }) else { throw BSmartAPIError.invalidResponse }
        try Task.checkCancellation()
        snapshot = Snapshot(signals: signals, updates: updates, accounts: accounts,
                            intelligence: intelligence, money: money, movements: movements)
        manifest = incoming
        freshnessState.commit(incoming)
        // Non-sensitive acceptance receipt: written only after authenticated remote pages
        // have all decoded and committed. It contains no identity, token or content body.
        if injectedRequest == nil {
            let receipt: [String: Any] = ["revision": incoming.revision,
                "verifiedAt": Date().ISO8601Format(), "authenticatedContentLoaded": true,
                "authors": accounts.count, "opinions": updates.count,
                "moneyAccounts": money.count, "movements": movements.count]
            if let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
               let data = try? JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]) {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? data.write(to: directory.appendingPathComponent("ContentVerification.json"), options: .atomic)
            }
        }
    }

    private func collection<T: Decodable>(_ name: String, in incoming: SupabaseContentManifest,
                                          previous: [T]?) async throws -> [T] {
        if manifest?.collections[name]?.sha256 == incoming.collections[name]?.sha256, let previous { return previous }
        return try await readPages(name, owner: "_", revision: incoming.revision, expectedCount: incoming.collections[name]?.count)
    }

    private func readPages<T: Decodable>(_ name: String, owner: String, revision: String,
                                        expectedCount: Int? = nil) async throws -> [T] {
        var items: [T] = [], index = 0, pages = 1, total: Int?
        repeat {
            let data = try await request("page", query: [.init(name: "revision", value: revision),
                .init(name: "collection", value: name), .init(name: "owner", value: owner),
                .init(name: "page", value: String(index))])
            let result = try BSmartJSONCoding.makeDecoder().decode(SupabaseContentPage<T>.self, from: data)
            guard result.revision == revision, result.page == index, (1...10000).contains(result.pages),
                  result.pages > index, (0...1_000_000).contains(result.total), result.items.count <= 100,
                  total == nil || total == result.total, index == 0 || pages == result.pages,
                  expectedCount == nil || expectedCount == result.total else { throw BSmartAPIError.invalidResponse }
            pages = result.pages; total = result.total
            items.append(contentsOf: result.items)
            guard items.count <= result.total, !result.items.isEmpty || (result.total == 0 && pages == 1) else {
                throw BSmartAPIError.invalidResponse
            }
            index += 1
        } while index < pages
        guard items.count == total else { throw BSmartAPIError.invalidResponse }
        return items
    }

    private func current() throws -> Snapshot {
        guard let snapshot else { throw BSmartAPIError.invalidResponse }
        return snapshot
    }

    func fetchPortfolio() async throws -> [PortfolioPosition] { [] }
    func fetchPortfolioHistory() async throws -> [PortfolioValuePoint] { [] }
    func fetchSignals() async throws -> [PortfolioSignal] { try current().signals }
    func fetchSmartAccountUpdates() async throws -> [SmartAccountUpdate] { try current().updates }
    func fetchSmartMoneyMovements() async throws -> [SmartMoneyMovement] { try current().movements }
    func fetchTickerIntelligence() async throws -> [TickerIntelligence] { try current().intelligence }
    func fetchSmartAccounts() async throws -> [SmartAccountProfile] { try current().accounts }
    func fetchSmartMoney() async throws -> [SmartMoneySignal] { try current().money }

    func fetchSmartAccountEvidence(accountID: String) async throws -> [SmartAccountUpdate] {
        guard let revision = manifest?.revision else { throw BSmartAPIError.invalidResponse }
        let items: [SmartAccountUpdate] = try await readPages("smart-account-evidence", owner: accountID, revision: revision)
        guard revision == manifest?.revision else { throw CancellationError() }
        guard items.allSatisfy({ $0.authorId == accountID }) else { throw BSmartAPIError.invalidResponse }
        return items
    }

    func fetchSmartMoneyEvidence(accountID: String) async throws -> [SmartMoneyRepresentativeEvidence] {
        guard let revision = manifest?.revision else { throw BSmartAPIError.invalidResponse }
        let items: [SmartMoneyRepresentativeEvidence] = try await readPages("smart-money-evidence", owner: accountID, revision: revision)
        guard revision == manifest?.revision else { throw CancellationError() }
        guard items.allSatisfy({ $0.accountId == accountID }) else { throw BSmartAPIError.invalidResponse }
        return items
    }
}
