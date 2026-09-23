import XCTest
@testable import BSmart

@MainActor
final class NativeFeedSessionTests: XCTestCase {
    func testPrivyReceivesOnlyMatchingSupabaseAccessTokenAndLogoutInvalidatesScope() async throws {
        let (store, session) = await signedIn()
        let token = try await store.embeddedWalletAccessToken(expectedAccountID: session.account.id)
        XCTAssertEqual(token, session.accessToken)
        await expectJournalFailure { try await store.embeddedWalletAccessToken(expectedAccountID: UUID()) }
        let revision = store.walletSessionRevision
        await store.signOut()
        XCTAssertNotEqual(store.walletSessionRevision, revision)
        await expectJournalFailure { try await store.embeddedWalletAccessToken(expectedAccountID: session.account.id) }
        let (legacy, legacySession) = await signedIn(authority: nil)
        await expectJournalFailure { try await legacy.embeddedWalletAccessToken(expectedAccountID: legacySession.account.id) }
    }

    func testFeedUsesSupabaseIdentityWithoutWalletOrInstallationToken() async throws {
        let (store, session) = await signedIn()
        let value = try await store.withFeedSession(expectedAccountID: session.account.id) { token in
            XCTAssertEqual(token, session.accessToken)
            return "response"
        }
        XCTAssertEqual(value, "response")
        XCTAssertFalse(store.configuration.tradingEnabled)
    }

    func testWrongAccountAndLegacySessionCannotMakeFeedRequest() async {
        let (store, _) = await signedIn()
        do {
            _ = try await store.withFeedSession(expectedAccountID: UUID()) { _ in XCTFail("Must not send"); return 1 }
            XCTFail("Must reject wrong identity")
        } catch { }
        let (legacy, _) = await signedIn(authority: nil)
        do {
            _ = try await legacy.withFeedSession { _ in XCTFail("Must not use legacy token"); return 1 }
            XCTFail("Must reject legacy identity")
        } catch { }
    }

    func testLogoutDropsLateFeedResponse() async {
        let (store, _) = await signedIn()
        do {
            _ = try await store.withFeedSession { _ in await store.signOut(); return "stale identity" }
            XCTFail("Must drop response after logout")
        } catch { }
        XCTAssertNil(store.identity)
    }

    func testSharingInvalidatesPublicViewsOnlyForMatchingAccount() async {
        let (store, session) = await signedIn()
        store.feedSharingDidChange(accountID: UUID())
        XCTAssertEqual(store.feedRevision, 0)
        store.feedSharingDidChange(accountID: session.account.id)
        XCTAssertEqual(store.feedRevision, 1)
    }

    func testLogoutUnregisterHookReceivesSavedTokenAfterLocalIdentityIsCleared() async {
        let (store, session) = await signedIn()
        var calls = 0
        store.onSessionEnding = { token in
            calls += 1
            XCTAssertEqual(token, session.accessToken)
            XCTAssertNil(store.identity)
            XCTAssertFalse(store.canAccessAppContent)
        }
        await store.signOut()
        XCTAssertEqual(calls, 1)
    }

    func testFeedSourceIncludesAuthorAndPayloadContainsNoPrivateSigningData() throws {
        let source = OpinionTradeSource(opinionID: UUID(), ticker: "NVDA", authorID: "x:author")
        let order = try HyperliquidOrderTestSupport.order()
        let payload = try NativeOpinionOrderAttribution.registration(source: source, order: order)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["opinionId", "authorId", "ticker", "cloid", "coin", "side", "size", "limitPrice", "nonce", "expiresAfter"])
        XCTAssertEqual(json["cloid"] as? String, order.cloid)
        XCTAssertThrowsError(try NativeOpinionOrderAttribution.registration(
            source: .init(opinionID: UUID(), ticker: "NVDA"), order: order))
    }

    private func signedIn(authority: AccountSessionAuthority? = .supabase) async -> (AccountAccessStore, TradingAccountSession) {
        let session = TradingAccountSession(account: .init(id: UUID(), provider: .google),
            accessToken: authority == .supabase ? "eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.disposableSignatureForTests" : String(repeating: "x", count: 64),
            expiresAt: Date().addingTimeInterval(1800), authority: authority)
        let store = AccountAccessStore(client: FeedSessionAuth(identity: session.account), storage: FeedSessionMemory(session))
        await store.load()
        return (store, session)
    }
}

private final class FeedSessionMemory: AccountSessionPersisting {
    var session: TradingAccountSession?
    init(_ value: TradingAccountSession) { session = value }
    func load() throws -> TradingAccountSession? { session }
    func save(_ value: TradingAccountSession) throws { session = value }
    func clear() throws { session = nil }
}

private struct FeedSessionAuth: AccountAuthenticating {
    let identity: TradingAccountIdentity
    func configuration() async throws -> AccountAuthConfiguration { .init(providers: [.google], depositsEnabled: false, tradingEnabled: false) }
    func account(token: String) async throws -> TradingAccountIdentity { identity }
    func signOut(token: String) async throws { }
    func challenge(provider: AccountIdentityProvider) async throws -> AccountAuthChallenge { throw AccountAccessError.unavailable }
    func signIn(provider: AccountIdentityProvider, challenge: UUID, assertion: AccountIdentityAssertion) async throws -> TradingAccountSession {
        throw AccountAccessError.unavailable
    }
}
