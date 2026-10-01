import Foundation

@MainActor
final class InvestorAbilityLeaderboardStore: ObservableObject {
    @Published private(set) var snapshot: InvestorAbilityLeaderboard?
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    private var requestID = UUID()

    func clear() {
        requestID = UUID(); snapshot = nil; loading = false; failed = false
    }

    func load(fetch: () async throws -> InvestorAbilityLeaderboard) async {
        let token = UUID()
        requestID = token; loading = true; failed = false
        defer { if requestID == token { loading = false } }
        do {
            let result = try await fetch().validate()
            try Task.checkCancellation()
            guard requestID == token else { return }
            snapshot = result
        } catch {
            guard requestID == token, !Task.isCancelled else { return }
            failed = true
        }
    }
}
