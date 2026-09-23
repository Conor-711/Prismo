import Foundation

@MainActor
final class TradeFeedStore: ObservableObject {
    @Published private(set) var items: [TradeFeedItem] = []
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var nextOffset: Int?
    private var requestID = UUID()

    func clear() {
        requestID = UUID()
        items = []
        nextOffset = nil
        loading = false
        failed = false
        hasLoaded = false
    }

    func load(reset: Bool, fetch: (Int) async throws -> TradeFeedPage) async {
        if !reset && (loading || nextOffset == nil) { return }
        let identifier = UUID()
        requestID = identifier
        let offset = reset ? 0 : nextOffset ?? 0
        loading = true
        failed = false
        defer { if requestID == identifier { loading = false } }
        do {
            let page = try await fetch(offset)
            try Task.checkCancellation()
            try page.validate(offset: offset)
            guard requestID == identifier else { return }
            if reset { items = page.items } else {
                let ids = Set(page.items.map(\.id))
                items.removeAll { ids.contains($0.id) }
                items.append(contentsOf: page.items)
            }
            items.sort { $0.executedAt != $1.executedAt ? $0.executedAt > $1.executedAt : $0.id.uuidString < $1.id.uuidString }
            nextOffset = page.nextOffset
            hasLoaded = true
        } catch {
            guard requestID == identifier else { return }
            // A cancelled view task is not a failed server refresh.
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            // Public consent may have changed; stale identities are not a refresh fallback.
            if reset { items = []; nextOffset = nil; hasLoaded = false }
            failed = true
        }
    }
}
