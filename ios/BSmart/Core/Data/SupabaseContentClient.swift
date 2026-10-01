import Foundation

/// Research only. Private portfolio state and authenticated trading have separate owners.
@MainActor
final class SupabaseContentClient: BSmartAPIClient, BSmartContentRefreshing, BSmartDataFreshnessProviding, BSmartSubjectActivityProviding {
    typealias Request = (String, [URLQueryItem]) async throws -> Data
    private let configuration: SupabaseAccountConfiguration?
    private let injectedRequest: Request?
    private let cacheURL: URL?
    private weak var account: AccountAccessStore?
    private var transport: SupabaseAccountTransport?
    private var manifest: SupabaseContentManifest?
    private var refreshTask: Task<Void, Error>?
    private var snapshot: Snapshot?
    private var cacheRestoreTask: Task<StoredSnapshot?, Never>?
    private nonisolated let freshnessState = SupabaseContentFreshness()

    private struct Snapshot: Codable {
        let signals: [PortfolioSignal]
        let updates: [SmartAccountUpdate]
        let accounts: [SmartAccountProfile]
        let intelligence: [TickerIntelligence]
        let money: [SmartMoneySignal]
        let movements: [SmartMoneyMovement]
    }

    private struct StoredSnapshot: Codable {
        let manifest: SupabaseContentManifest
        let snapshot: Snapshot

        var isValid: Bool {
            guard (try? manifest.validate()) != nil else { return false }
            let counts = manifest.collections
            let authorIDs = Set(snapshot.accounts.map(\.id))
            return counts["portfolio-signals"]?.count == snapshot.signals.count
                && counts["smart-account-updates"]?.count == snapshot.updates.count
                && counts["smart-accounts"]?.count == snapshot.accounts.count
                && counts["ticker-intelligence"]?.count == snapshot.intelligence.count
                && counts["smart-money"]?.count == snapshot.money.count
                && counts["smart-money-movements"]?.count == snapshot.movements.count
                && !snapshot.accounts.isEmpty
                && authorIDs.count == snapshot.accounts.count
                && snapshot.updates.allSatisfy { authorIDs.contains($0.authorId) }
        }
    }

    init(configuration: SupabaseAccountConfiguration? = nil, request: Request? = nil, cacheURL: URL? = nil) {
        self.configuration = configuration
        self.injectedRequest = request
        if let cacheURL { self.cacheURL = cacheURL }
        else if let configuration, request == nil {
            self.cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("ContentSnapshot-\(configuration.url.host ?? "unknown").json")
        } else { self.cacheURL = nil }
        transport = configuration.map { SupabaseAccountTransport(configuration: $0) }
        if let path = self.cacheURL {
            cacheRestoreTask = Task {
                await BSmartContentIO.shared.read(StoredSnapshot.self, from: path)
            }
        }
    }

    func restoreCachedSnapshot() async {
        guard let task = cacheRestoreTask else { return }
        let stored = await task.value
        cacheRestoreTask = nil
        if snapshot == nil, let stored, stored.isValid {
            manifest = stored.manifest
            snapshot = stored.snapshot
            freshnessState.commit(stored.manifest)
        }
    }

    var hasCachedSnapshot: Bool { manifest != nil && snapshot != nil }

    func bind(account: AccountAccessStore) { self.account = account }

    nonisolated var latestDataAsOf: Date? { freshnessState.latest }
    nonisolated func freshness(for source: BSmartLiveDataSource) -> BSmartDataFreshness? { freshnessState.value(for: source) }

    func prepareContentRefresh() async throws {
        await restoreCachedSnapshot()
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
        for attempt in 0..<3 {
            do {
                return try await account.withFeedSession { token in
                    try await transport.request("functions/v1/bsmart-content/" + path, query: query, token: token)
                }
            } catch {
                try Task.checkCancellation()
                let retryable = (error as? AccountAccessError) == .unavailable
                    || (error as? URLError).map {
                        [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet].contains($0.code)
                    } == true
                guard attempt < 2, retryable else { throw error }
                try await Task.sleep(for: .milliseconds(attempt == 0 ? 300 : 800))
            }
        }
        throw AccountAccessError.unavailable
    }

    private func stageSnapshot() async throws {
        let data = try await request("manifest")
        let incoming = try await BSmartContentIO.shared.decode(SupabaseContentManifest.self, from: data, iso8601Dates: true)
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
        let next = Snapshot(signals: signals, updates: updates, accounts: accounts,
                            intelligence: intelligence, money: money, movements: movements)
        snapshot = next
        manifest = incoming
        freshnessState.commit(incoming)
        if let cacheURL {
            _ = try? await BSmartContentIO.shared.persist(StoredSnapshot(manifest: incoming, snapshot: next), to: cacheURL)
        }
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
        func query(_ index: Int) -> [URLQueryItem] {
            [.init(name: "revision", value: revision), .init(name: "collection", value: name),
             .init(name: "owner", value: owner), .init(name: "page", value: String(index))]
        }
        let firstData = try await request("page", query: query(0))
        let first = try await BSmartContentIO.shared.decode(SupabaseContentPage<T>.self, from: firstData, iso8601Dates: true)
        guard first.revision == revision, first.page == 0, (1...10000).contains(first.pages),
              (0...1_000_000).contains(first.total), first.items.count <= 100,
              !first.items.isEmpty || (first.total == 0 && first.pages == 1),
              expectedCount == nil || expectedCount == first.total else { throw BSmartAPIError.invalidResponse }
        var items = first.items
        for start in stride(from: 1, to: first.pages, by: 4) {
            let end = min(start + 4, first.pages)
            let pageData = try await withThrowingTaskGroup(of: (Int, Data).self) { group in
                for index in start..<end {
                    group.addTask { [self] in (index, try await self.request("page", query: query(index))) }
                }
                var received: [Int: Data] = [:]
                for try await (index, data) in group { received[index] = data }
                return received
            }
            for index in start..<end {
                guard let data = pageData[index] else { throw BSmartAPIError.invalidResponse }
                let page = try await BSmartContentIO.shared.decode(SupabaseContentPage<T>.self, from: data, iso8601Dates: true)
                guard page.revision == revision, page.page == index, page.pages == first.pages,
                      page.total == first.total, page.items.count <= 100, !page.items.isEmpty,
                      items.count + page.items.count <= first.total else { throw BSmartAPIError.invalidResponse }
                items.append(contentsOf: page.items)
            }
        }
        guard items.count == first.total else { throw BSmartAPIError.invalidResponse }
        return items
    }

    private func current() async throws -> Snapshot {
        await restoreCachedSnapshot()
        guard let snapshot else { throw BSmartAPIError.invalidResponse }
        return snapshot
    }

    func fetchPortfolio() async throws -> [PortfolioPosition] { [] }
    func fetchPortfolioHistory() async throws -> [PortfolioValuePoint] { [] }
    func fetchSignals() async throws -> [PortfolioSignal] { try await current().signals }
    func fetchSmartAccountUpdates() async throws -> [SmartAccountUpdate] { try await current().updates }
    func fetchSmartMoneyMovements() async throws -> [SmartMoneyMovement] { try await current().movements }
    func fetchTickerIntelligence() async throws -> [TickerIntelligence] { try await current().intelligence }
    func fetchSmartAccounts() async throws -> [SmartAccountProfile] { try await current().accounts }
    func fetchSmartMoney() async throws -> [SmartMoneySignal] { try await current().money }

    func fetchSubjectActivity() async throws -> TodaySubjectFeedSnapshot {
        let data = try await request("subject-activity")
        guard data.count <= 8_388_608 else { throw BSmartAPIError.invalidResponse }
        let snapshot = try await BSmartContentIO.shared.subjectSnapshot(from: data)
        return snapshot
    }

    func fetchSubjectActivity(subjectID: String) async throws -> TodaySubjectFeedSnapshot {
        let data = try await request("subject-activity", query: [URLQueryItem(name: "subjectID", value: subjectID)])
        guard data.count <= 8_388_608 else { throw BSmartAPIError.invalidResponse }
        let snapshot = try await BSmartContentIO.shared.subjectSnapshot(from: data)
        guard snapshot.subjects.count == 1, snapshot.subjects[0].id == subjectID,
              snapshot.events.allSatisfy({ $0.subjectID == subjectID })
        else { throw BSmartAPIError.invalidResponse }
        return snapshot
    }

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

extension BSmartContentIO {
    func subjectSnapshot(from data: Data) throws -> TodaySubjectFeedSnapshot {
        let snapshot = try decode(TodaySubjectFeedSnapshot.self, from: data)
        guard snapshot.isValid else { throw BSmartAPIError.invalidResponse }
        return snapshot
    }
}
