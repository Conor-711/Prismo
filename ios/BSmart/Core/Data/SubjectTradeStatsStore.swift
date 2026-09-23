import Foundation

@MainActor
final class SubjectTradeStatsStore: ObservableObject {
    @Published private(set) var stats: SubjectTradeStats?
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    private var requestID = UUID()

    func clear() {
        requestID = UUID(); stats = nil; loading = false; failed = false
    }

    func load(subject: TradeSubject, fetch: () async throws -> SubjectTradeStats) async {
        let token = UUID()
        requestID = token; loading = true; failed = false; stats = nil
        defer { if requestID == token { loading = false } }
        do {
            let result = try await fetch()
            try Task.checkCancellation()
            try result.validate(subject: subject)
            guard requestID == token else { return }
            stats = result
        } catch {
            guard requestID == token else { return }
            failed = !Task.isCancelled
        }
    }
}
