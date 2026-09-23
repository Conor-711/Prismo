import XCTest
@testable import BSmart

@MainActor
final class ContentPushTests: XCTestCase {
    func testRegistrationRotationDisableAndLogout() async throws {
        let (account, registration) = await setup()
        AccountExchangeURLProtocol.configure(data: Data(#"{"registered":true}"#.utf8))
        registration.synchronize(token: String(repeating: "a", count: 64), enabled: true, locale: "zh-Hans", interests: interests(registration))
        await registration.finishPendingRegistration()
        XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 2)
        let first = try body()
        XCTAssertNil(first["userId"])
        XCTAssertEqual(first["notifyAuthors"] as? Bool, true)
        XCTAssertEqual(AccountExchangeURLProtocol.captured?.0.httpMethod, "PUT")
        registration.synchronize(token: String(repeating: "a", count: 64), enabled: true, locale: "zh-Hans", interests: interests(registration))
        await registration.finishPendingRegistration()
        XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 2)
        // Rapid off/on must not let the successful old registration suppress the final on.
        registration.synchronize(token: nil, enabled: false, locale: "zh-Hans", interests: interests(registration))
        registration.synchronize(token: String(repeating: "b", count: 64), enabled: true, locale: "zh-Hans", interests: interests(registration))
        await registration.finishPendingRegistration()
        XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 5)
        XCTAssertEqual(try body()["installationId"] as? String, first["installationId"] as? String)
        await account.signOut()
        XCTAssertEqual(AccountExchangeURLProtocol.captured?.0.httpMethod, "DELETE")
        XCTAssertNil(account.identity)
    }

    func testFailureRetriesAndDeniedPermissionDoesNotNeedToken() async throws {
        let (account, registration) = await setup()
        AccountExchangeURLProtocol.configure(status: 503, data: Data("{}".utf8))
        var successes: [Bool] = []
        registration.onResult = { successes.append($0) }
        registration.synchronize(token: nil, enabled: false, locale: "en", interests: interests(registration))
        await registration.finishPendingRegistration()
        XCTAssertEqual(successes, [false])
        AccountExchangeURLProtocol.configure(data: Data(#"{"registered":false}"#.utf8))
        registration.synchronize(token: nil, enabled: false, locale: "en", interests: interests(registration))
        await registration.finishPendingRegistration()
        XCTAssertEqual(successes, [false, true])
        XCTAssertEqual(AccountExchangeURLProtocol.captured?.0.httpMethod, "DELETE")
        XCTAssertNotNil(account.identity)
    }

    func testTestLoginNeverRegistersForCloudPush() async {
        let account = AccountAccessStore(client: nil, storage: PushSessionMemory(nil))
        await account.load()
        account.startTestSession()
        let registration = makeRegistration()
        registration.bind(account: account)
        AccountExchangeURLProtocol.configure(data: Data("{}".utf8))
        registration.synchronize(token: String(repeating: "a", count: 64), enabled: true, locale: "en", interests: interests(registration))
        await registration.finishPendingRegistration()
        XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 0)
    }

    private func setup() async -> (AccountAccessStore, ContentPushRegistration) {
        let session = TradingAccountSession(account: .init(id: UUID(), provider: .google),
            accessToken: "eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.disposableSignatureForTests",
            expiresAt: Date().addingTimeInterval(1800), authority: .supabase)
        let account = AccountAccessStore(client: PushAuth(identity: session.account), storage: PushSessionMemory(session))
        await account.load()
        let registration = makeRegistration()
        registration.bind(account: account)
        return (account, registration)
    }

    private func makeRegistration() -> ContentPushRegistration {
        let defaults = UserDefaults(suiteName: "bsmart.push.tests.\(UUID())")!
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AccountExchangeURLProtocol.self]
        return ContentPushRegistration(configuration: .init(url: "https://test.supabase.co",
            publishableKey: "sb_publishable_disposable_public_test_key"), defaults: defaults, sessionConfiguration: config)
    }

    private func interests(_ registration: ContentPushRegistration) -> ContentPushInterests {
        .init(installationId: registration.installationId, authors: ["x:author"], money: [],
              tickers: ["GME"], holdings: [], notifyAuthors: true, notifyTickers: true, notifyHoldings: true)
    }

    private func body() throws -> [String: Any] {
        let data = try XCTUnwrap(AccountExchangeURLProtocol.captured?.1)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class PushSessionMemory: AccountSessionPersisting {
    var session: TradingAccountSession?
    init(_ value: TradingAccountSession?) { session = value }
    func load() throws -> TradingAccountSession? { session }
    func save(_ value: TradingAccountSession) throws { session = value }
    func clear() throws { session = nil }
}

private struct PushAuth: AccountAuthenticating {
    let identity: TradingAccountIdentity
    func configuration() async throws -> AccountAuthConfiguration { .init(providers: [.google], depositsEnabled: false, tradingEnabled: false) }
    func account(token: String) async throws -> TradingAccountIdentity { identity }
    func signOut(token: String) async throws {}
    func challenge(provider: AccountIdentityProvider) async throws -> AccountAuthChallenge { throw AccountAccessError.unavailable }
    func signIn(provider: AccountIdentityProvider, challenge: UUID, assertion: AccountIdentityAssertion) async throws -> TradingAccountSession {
        throw AccountAccessError.unavailable
    }
}
