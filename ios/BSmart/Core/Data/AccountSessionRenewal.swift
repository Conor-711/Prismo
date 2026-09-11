import Foundation

@MainActor
final class AccountSessionRenewal {
    private let client: AccountAuthenticating
    private let storage: AccountSessionPersisting
    private var generation = UUID()
    private var pending: (source: TradingAccountSession, task: Task<TradingAccountSession, Error>)?

    init(client: AccountAuthenticating, storage: AccountSessionPersisting) {
        self.client = client; self.storage = storage
    }

    func renew(_ previous: TradingAccountSession) async throws -> TradingAccountSession {
        if let pending, pending.source == previous { return try await pending.task.value }
        guard let refresh = previous.refreshToken, previous.hasValidRefreshToken,
              let expiry = previous.refreshExpiresAt, expiry > Date() else { throw AccountAccessError.expired }
        // Durable before sending: a crash or lost response must not replay the old credential.
        try storage.beginRenewal(previous)
        cancel()
        let generation = self.generation
        let task = Task { @MainActor in
            let replacement = try await client.refresh(token: refresh, provider: previous.account.provider)
            do {
                try Task.checkCancellation()
                guard generation == self.generation else { throw CancellationError() }
                try replacement.validateRenewal(of: previous)
                try storage.completeRenewal(replacement, replacing: previous)
                return replacement
            } catch {
                let cleanup = Task { try? await client.signOut(token: replacement.accessToken) }
                await cleanup.value
                throw error
            }
        }
        pending = (previous, task)
        return try await task.value
    }

    func cancel() {
        generation = UUID()
        pending?.task.cancel()
        pending = nil
    }
}
