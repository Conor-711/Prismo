import Foundation

@MainActor
final class AccountDeletionReauthentication {
    private let client: AccountAuthenticating
    private let apple: AppleCredentialMonitor
    init(client: AccountAuthenticating, apple: AppleCredentialStateChecking? = nil) {
        self.client = client
        self.apple = AppleCredentialMonitor(client: apple ?? NativeAppleCredentialStateClient(), now: Date.init)
    }

    func authorize(expected: TradingAccountIdentity,
                   authorize: (AccountAuthChallenge) async throws -> AccountIdentityAssertion) async throws
        -> (session: TradingAccountSession, googleUserID: String?) {
        try Task.checkCancellation()
        let challenge = try await client.challenge(provider: expected.provider)
        guard challenge.expiresAt > Date(), challenge.nonce.count >= 32 else { throw AccountAccessError.invalidResponse }
        let assertion = try await authorize(challenge)
        try assertion.validate(for: expected.provider)
        try Task.checkCancellation()
        guard challenge.expiresAt > Date() else { throw AccountAccessError.expired }
        let verified = try await client.reauthenticate(account: expected, challenge: challenge.id, assertion: assertion)
        do {
            try Task.checkCancellation()
            guard verified.account == expected else { throw AccountDeletionError.accountChanged }
            try verified.validateReceipt()
            if expected.provider == .apple { _ = try await apple.authorize(userID: assertion.appleUserID) }
            else if assertion.googleUserID == nil { throw AccountDeletionError.providerDisconnectRequired }
            try Task.checkCancellation()
            return (verified, assertion.googleUserID)
        } catch {
            let cleanup = Task {
                if let refresh = verified.refreshToken { try? await client.revokeRefresh(token: refresh) }
                else { try? await client.signOut(token: verified.accessToken) }
            }
            await cleanup.value
            throw error
        }
    }
}
