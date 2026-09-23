import Foundation

@MainActor
final class PopularOpinionsStore: ObservableObject {
    @Published private(set) var items: [PopularOpinion] = []
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var nextOffset: Int?
    private var requestID = UUID()

    func clear() {
        requestID = UUID(); items = []; nextOffset = nil
        loading = false; failed = false; hasLoaded = false
    }

    func load(reset: Bool, fetch: (Int) async throws -> PopularOpinionsPage) async {
        if !reset && (loading || nextOffset == nil) { return }
        let token = UUID(), offset = reset ? 0 : nextOffset ?? 0
        requestID = token; loading = true; failed = false
        defer { if requestID == token { loading = false } }
        do {
            let page = try await fetch(offset)
            try Task.checkCancellation()
            try page.validate(offset: offset)
            guard requestID == token else { return }
            if reset { items = page.items } else {
                let ids = Set(page.items.map(\.id))
                items.removeAll { ids.contains($0.id) }
                items.append(contentsOf: page.items)
                // Keep server order for ties while deduplicating a changing leaderboard.
                items = items.enumerated().sorted {
                    $0.element.totalTraders == $1.element.totalTraders ? $0.offset < $1.offset
                        : $0.element.totalTraders > $1.element.totalTraders
                }.map(\.element)
            }
            nextOffset = page.nextOffset; hasLoaded = true
        } catch {
            guard requestID == token else { return }
            if reset { items = []; nextOffset = nil; hasLoaded = false }
            failed = !Task.isCancelled
        }
    }
}
