import Foundation

@MainActor
final class DiscoveryRankingsStore: ObservableObject {
    @Published private(set) var items: [DiscoveryRankingItem] = []
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var nextOffset: Int?
    private var anchor: Date?
    private var query: DiscoveryRankingQuery?
    private var requestID = UUID()

    func clear() {
        requestID = UUID(); items = []; nextOffset = nil; anchor = nil; query = nil
        loading = false; failed = false; hasLoaded = false
    }

    func load(query: DiscoveryRankingQuery, limit: Int, reset: Bool,
              fetch: (Int, Date?) async throws -> DiscoveryRankingsPage) async {
        let reset = reset || self.query != query
        if !reset && (loading || nextOffset == nil) { return }
        if reset { clear() }
        self.query = query
        let token = UUID(), offset = reset ? 0 : nextOffset ?? 0
        let expectedAnchor = reset ? nil : anchor
        requestID = token; loading = true; failed = false
        defer { if requestID == token { loading = false } }
        do {
            let page = try await fetch(offset, expectedAnchor)
            try Task.checkCancellation()
            try page.validate(query: query, offset: offset, limit: limit, anchor: expectedAnchor)
            guard requestID == token else { return }
            let ids = Set(page.items.map(\.id))
            items.removeAll { ids.contains($0.id) }
            items.append(contentsOf: page.items)
            items.sort { $0.precedes($1, sort: query.sort) }
            anchor = page.asOf; nextOffset = page.nextOffset; hasLoaded = true
        } catch {
            guard requestID == token else { return }
            failed = !Task.isCancelled
        }
    }
}
