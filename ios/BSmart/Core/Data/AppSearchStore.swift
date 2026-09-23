import Foundation

struct PublicProfileSearchPage: Decodable {
    let items: [FeedPublicProfile]
    let nextOffset: Int?
    func validate(offset: Int) throws {
        guard (0...10000).contains(offset), items.count <= 20, items.allSatisfy(\.isValid), Set(items.map(\.id)).count == items.count,
              nextOffset == nil || (!items.isEmpty && nextOffset == offset + items.count && nextOffset! <= 10000) else {
            throw BSmartAPIError.invalidResponse
        }
    }
}

@MainActor
struct PublicProfileSearchClient {
    let account: AccountAccessStore
    func search(query: String, offset: Int) async throws -> PublicProfileSearchPage {
        guard let config = SupabaseAccountConfiguration.resolve() else { throw AccountAccessError.unavailable }
        return try await account.withFeedSession { token in
            let data = try await SupabaseAccountTransport(configuration: config).request("functions/v1/bsmart-search/profiles",
                query: [.init(name: "q", value: query), .init(name: "offset", value: String(offset)),
                        .init(name: "limit", value: "20")], token: token)
            let page = try BSmartJSONCoding.makeDecoder().decode(PublicProfileSearchPage.self, from: data)
            try page.validate(offset: offset)
            return page
        }
    }
}

@MainActor
final class AppSearchStore: ObservableObject {
    @Published private(set) var results: [AppSearchItem] = []
    @Published private(set) var users: [FeedPublicProfile] = []
    @Published private(set) var searching = false
    @Published private(set) var usersLoading = false
    @Published private(set) var usersFailed = false
    @Published private(set) var nextUserOffset: Int?
    @Published private(set) var recentQueries: [String] = []
    private var index = AppSearchIndex()
    private var generation = UUID()
    private var indexGeneration = UUID()
    private var activeQuery = ""
    private var historyKey: String?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func setAccount(_ id: UUID?) {
        cancel()
        historyKey = id.map { "bsmart.search-history.v1.\($0.uuidString)" }
        let saved = historyKey.flatMap { defaults.stringArray(forKey: $0) } ?? []
        recentQueries = Array(saved.filter { !$0.isEmpty && $0.count <= 80 }.prefix(8))
    }
    func remember(_ raw: String) {
        let text = AppSearchQuery(raw).text
        guard !text.isEmpty, text.count <= 80 else { return }
        recentQueries.removeAll { AppSearchQuery.fold($0) == AppSearchQuery.fold(text) }
        recentQueries.insert(text, at: 0)
        recentQueries = Array(recentQueries.prefix(8))
        if let historyKey { defaults.set(recentQueries, forKey: historyKey) }
    }
    func clearHistory() {
        recentQueries = []
        if let historyKey { defaults.removeObject(forKey: historyKey) }
    }
    func cancel() {
        generation = UUID()
        users = []; results = []; nextUserOffset = nil
        searching = false; usersLoading = false; usersFailed = false
    }
    func replaceIndex(items: [AppSearchItem]) async {
        let ticket = UUID(); indexGeneration = ticket
        let value = await Task.detached(priority: .userInitiated) { AppSearchIndex(items: items) }.value
        guard !Task.isCancelled, indexGeneration == ticket else { return }
        index = value
    }
    func search(_ raw: String, fetchUsers: ((String, Int) async throws -> PublicProfileSearchPage)?,
                debounce: Bool = true) async {
        cancel()
        let ticket = generation
        let query = AppSearchQuery(raw).text
        activeQuery = query
        guard query.count <= 80 else { return }
        searching = !query.isEmpty
        do {
            if debounce { try await Task.sleep(for: .milliseconds(220)) }
            try Task.checkCancellation()
            guard generation == ticket else { return }
            if !query.isEmpty {
                let currentIndex = index
                let found = await Task.detached(priority: .userInitiated) { currentIndex.search(query) }.value
                guard generation == ticket, !Task.isCancelled else { return }
                results = found
            }
            searching = false
            if let fetchUsers { await loadUsers(reset: true, ticket: ticket, fetch: fetchUsers) }
        } catch {
            if generation == ticket { searching = false }
        }
    }
    func moreUsers(fetch: (String, Int) async throws -> PublicProfileSearchPage) async {
        guard !usersLoading, nextUserOffset != nil else { return }
        await loadUsers(reset: false, ticket: generation, fetch: fetch)
    }
    func retryUsers(fetch: (String, Int) async throws -> PublicProfileSearchPage) async {
        guard !usersLoading else { return }
        await loadUsers(reset: true, ticket: generation, fetch: fetch)
    }
    private func loadUsers(reset: Bool, ticket: UUID, fetch: (String, Int) async throws -> PublicProfileSearchPage) async {
        let offset = reset ? 0 : nextUserOffset ?? 0
        usersLoading = true; usersFailed = false
        defer { if generation == ticket { usersLoading = false } }
        do {
            let page = try await fetch(activeQuery, offset)
            try Task.checkCancellation()
            try page.validate(offset: offset)
            guard generation == ticket else { return }
            if reset { users = page.items } else {
                var ids = Set(users.map(\.id))
                users += page.items.filter { ids.insert($0.id).inserted }
            }
            nextUserOffset = page.nextOffset
        } catch {
            guard generation == ticket else { return }
            usersFailed = !Task.isCancelled
            if reset { users = []; nextUserOffset = nil }
        }
    }
}
