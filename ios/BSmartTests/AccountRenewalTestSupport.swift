import XCTest
@testable import BSmart

func renewalSession(account: TradingAccountIdentity = .init(id: UUID(), provider: .google),
                    version: String = "original", lifetime: TimeInterval = 1800) -> TradingAccountSession {
    .init(account: account, accessToken: "bsa_" + String(repeating: version, count: 8),
          expiresAt: Date().addingTimeInterval(lifetime), refreshToken: "bsr_" + String(repeating: version, count: 8),
          refreshExpiresAt: Date().addingTimeInterval(86400))
}

final class RenewalMemoryStorage: AccountSessionPersisting {
    var saved: TradingAccountSession?
    var pending = false
    var rejectsSave = false
    var rejectsBegin = false
    var begins = 0
    init(_ session: TradingAccountSession? = nil) { saved = session }
    func load() throws -> TradingAccountSession? { saved }
    func isRenewalPending() throws -> Bool { pending }
    func beginRenewal(_ session: TradingAccountSession) throws {
        guard !rejectsBegin, !pending, saved == session else { throw AccountAccessError.storage }
        pending = true; begins += 1
    }
    func save(_ session: TradingAccountSession) throws {
        guard !rejectsSave else { throw AccountAccessError.storage }
        saved = session; pending = false
    }
    func clear() throws { saved = nil; pending = false }
}

actor RenewalTestClient: AccountAuthenticating {
    let replacement: TradingAccountSession
    let suspend: Bool
    let failRevocation: Bool
    private var continuation: CheckedContinuation<TradingAccountSession, Error>?
    private(set) var refreshes: [String] = []
    private(set) var accessRevocations: [String] = []
    private(set) var familyRevocations: [String] = []
    private(set) var accountRequests: [String] = []
    private(set) var walletRequests: [String] = []
    init(_ replacement: TradingAccountSession, suspend: Bool = false, failRevocation: Bool = false) {
        self.replacement = replacement; self.suspend = suspend; self.failRevocation = failRevocation
    }
    func configuration() async throws -> AccountAuthConfiguration {
        .init(providers: [.google, .apple], depositsEnabled: false, tradingEnabled: false)
    }
    func challenge(provider: AccountIdentityProvider) async throws -> AccountAuthChallenge {
        .init(id: UUID(), nonce: String(repeating: "n", count: 43), expiresAt: Date().addingTimeInterval(300))
    }
    func signIn(provider: AccountIdentityProvider, challenge: UUID,
                assertion: AccountIdentityAssertion) async throws -> TradingAccountSession { replacement }
    func account(token: String) async throws -> TradingAccountIdentity {
        accountRequests.append(token); return replacement.account
    }
    func wallet(token: String) async throws -> TradingWalletRegistration {
        walletRequests.append(token); return .init(accountId: replacement.account.id, address: nil)
    }
    func signOut(token: String) async throws { accessRevocations.append(token) }
    func revokeRefresh(token: String) async throws {
        familyRevocations.append(token)
        if failRevocation { throw AccountAccessError.unavailable }
    }
    func refresh(token: String) async throws -> TradingAccountSession {
        refreshes.append(token)
        if suspend {
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        return replacement
    }
    func waitForRequest() async throws {
        for _ in 0..<1000 {
            if !refreshes.isEmpty { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw AccountAccessError.unavailable
    }
    func finish(failing: Bool = false) {
        guard let continuation else { XCTFail("No suspended renewal"); return }
        self.continuation = nil
        if failing { continuation.resume(throwing: URLError(.networkConnectionLost)) }
        else { continuation.resume(returning: replacement) }
    }
}
