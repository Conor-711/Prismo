import Foundation

struct AppleCredentialAuthorization {
    let checkedAt: Date
    let checkedInstant: ContinuousClock.Instant
    var expiresAt: Date { checkedAt.addingTimeInterval(60) }
    var deadline: ContinuousClock.Instant { checkedInstant.advanced(by: .seconds(60)) }

    func isValid(now: Date, instant: ContinuousClock.Instant) -> Bool {
        now >= checkedAt && now < expiresAt && instant >= checkedInstant && instant < deadline
    }
}

@MainActor
final class AppleCredentialMonitor {
    private let client: AppleCredentialStateChecking
    private let now: () -> Date
    private let continuousNow: () -> ContinuousClock.Instant
    private var generation = UUID()
    private var pending: (userID: String?, task: Task<AppleCredentialAuthorization, Error>)?

    init(client: AppleCredentialStateChecking, now: @escaping () -> Date,
         continuousNow: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.client = client; self.now = now; self.continuousNow = continuousNow
    }

    func authorize(userID: String?) async throws -> AppleCredentialAuthorization {
        if let pending, pending.userID == userID { return try await pending.task.value }
        invalidate()
        let generation = self.generation
        let task = Task { @MainActor in
            let status = try await client.check(userID: userID)
            try Task.checkCancellation()
            guard generation == self.generation else { throw CancellationError() }
            guard case .authorized = status else { throw AccountAccessError.expired }
            return AppleCredentialAuthorization(checkedAt: now(), checkedInstant: continuousNow())
        }
        pending = (userID, task)
        defer { if generation == self.generation { pending = nil } }
        return try await task.value
    }

    func invalidate() {
        generation = UUID()
        pending?.task.cancel()
        pending = nil
    }
}
