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
        // Supabase can recover a lost rotation response using the active token's parent.
        // Keep the durable marker, but do not treat it as permanent revocation.
        if previous.authority == .supabase, try storage.isRenewalPending() {
            guard try storage.load()?.hasSameCredentials(as: previous) == true else { throw AccountAccessError.storage }
        } else {
            try storage.beginRenewal(previous)
        }
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
                if previous.authority == .supabase, case AccountAccessError.storage = error {
                    // Protected Keychain may lock while rotation is in flight.
                    // Preserve the server session so its parent can recover on unlock.
                    throw error
                }
                let cleanup = Task { try? await client.signOut(token: replacement.accessToken) }
                await cleanup.value
                throw error
            }
        }
        pending = (previous, task)
        do { return try await task.value }
        catch {
            if previous.authority == .supabase, generation == self.generation { pending = nil }
            throw error
        }
    }

    func cancel() {
        generation = UUID()
        pending?.task.cancel()
        pending = nil
    }
}
