import XCTest
@testable import BSmart

final class SupabaseAccountAuthTests: XCTestCase {
    private let accountID = UUID(uuidString: "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb")!
    private let jwt = "eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.disposableSignatureForTests"
    private let publicKey = "sb_publishable_disposable_public_test_key"

    func testOrderLinkErrorsKeepActionableCodesWithoutTriggeringWalletRecovery() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SupabaseTestURLProtocol.self]
        let transport = SupabaseAccountTransport(configuration:
            SupabaseAccountConfiguration(url: "https://test.supabase.co", publishableKey: publicKey)!, sessionConfiguration: config)
        for (status, code, expected): (Int, String, OpinionLinkError) in [
            (422, "opinion_unavailable", .sourceUnavailable), (409, "attribution_conflict", .conflict),
            (422, "invalid_input", .invalidIntent), (429, "rate_limit", .rateLimit),
            (503, "feed_unavailable", .unavailable), (503, "unknown", .unavailable)] {
            SupabaseTestURLProtocol.configure { _ in (status, Data("{\"error\":\"\(code)\"}".utf8)) }
            do { _ = try await transport.request("functions/v1/bsmart-feed/orders", method: "POST", token: jwt)
                XCTFail("Failure accepted")
            } catch { XCTAssertEqual(error as? OpinionLinkError, expected) }
            XCTAssertEqual(SupabaseTestURLProtocol.requests.count, 1)
        }
        SupabaseTestURLProtocol.configure { _ in (401, Data("{}".utf8)) }
        do { _ = try await transport.request("functions/v1/bsmart-feed/orders", token: jwt); XCTFail("Expired auth accepted") }
        catch { XCTAssertEqual(error as? AccountAccessError, .expired) }
    }

    func testAcrossErrorsDoNotMasqueradeAsSignInFailures() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SupabaseTestURLProtocol.self]
        let transport = SupabaseAccountTransport(configuration:
            SupabaseAccountConfiguration(url: "https://test.supabase.co", publishableKey: publicKey)!,
            sessionConfiguration: config)
        for (status, code, expected): (Int, String, AcrossWithdrawalError) in [
            (422, "quote_unavailable", .quoteUnavailable),
            (503, "provider_unavailable", .providerUnavailable),
            (503, "provider_not_authorized", .providerNotAuthorized),
            (503, "withdrawal_unavailable", .unavailable),
            (409, "withdrawal_pending", .pending),
            (409, "quote_expired", .quoteExpired),
            (503, "unknown", .unavailable)] {
            SupabaseTestURLProtocol.configure { _ in (status, Data("{\"error\":\"\(code)\"}".utf8)) }
            do {
                _ = try await transport.request("functions/v1/bsmart-withdrawals/quote", method: "POST",
                                                token: jwt, expectedStatus: 201)
                XCTFail("Failure accepted")
            } catch { XCTAssertEqual(error as? AcrossWithdrawalError, expected) }
        }
        SupabaseTestURLProtocol.configure { _ in (401, Data("{}".utf8)) }
        do { _ = try await transport.request("functions/v1/bsmart-withdrawals", token: jwt); XCTFail("Expired auth accepted") }
        catch { XCTAssertEqual(error as? AccountAccessError, .expired) }
    }

    func testOnlyProjectHTTPSAndPublicClientKeysAreAccepted() {
        for url in ["http://test.supabase.co", "https://api.bsmart.today", "https://test.supabase.co.evil.invalid",
                    "https://user@test.supabase.co", "https://test.supabase.co?key=x", "https://test.supabase.co/auth"] {
            XCTAssertNil(SupabaseAccountConfiguration(url: url, publishableKey: publicKey))
        }
        XCTAssertNil(SupabaseAccountConfiguration(url: "https://test.supabase.co", publishableKey: "sb_secret_not_a_client_key"))
    }

    func testProfileConflictsDoNotTriggerWalletRecoveryAndWalletBehaviorIsUnchanged() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SupabaseTestURLProtocol.self]
        let transport = SupabaseAccountTransport(configuration:
            SupabaseAccountConfiguration(url: "https://test.supabase.co", publishableKey: publicKey)!, sessionConfiguration: config)
        SupabaseTestURLProtocol.configure { _ in (409, Data(#"{"error":"handle_taken"}"#.utf8)) }
        do { _ = try await transport.request("functions/v1/bsmart-profile", token: jwt); XCTFail("Conflict accepted") }
        catch AccountProfileError.handleTaken {} catch { XCTFail("Unexpected: \(error)") }
        do { _ = try await transport.request("functions/v1/bsmart-wallet", token: jwt); XCTFail("Conflict accepted") }
        catch DeviceWalletError.recoveryRequired {} catch { XCTFail("Wallet behavior changed: \(error)") }
    }

    func testProfileConflictErrorBodyIsBounded() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SupabaseTestURLProtocol.self]
        let transport = SupabaseAccountTransport(configuration:
            SupabaseAccountConfiguration(url: "https://test.supabase.co", publishableKey: publicKey)!, sessionConfiguration: config)
        SupabaseTestURLProtocol.configure { _ in (409, Data(repeating: 32, count: 4097)) }
        do { _ = try await transport.request("functions/v1/bsmart-profile", token: jwt); XCTFail("Oversize accepted") }
        catch AccountAccessError.invalidResponse {} catch { XCTFail("Unexpected: \(error)") }
    }

    func testGoogleAndAppleExchangeNonceDirectlyWithSupabase() async throws {
        for provider in AccountIdentityProvider.allCases {
            configure(provider: provider)
            let client = makeClient()
            let challenge = try await client.challenge(provider: provider)
            XCTAssertNotEqual(challenge.nonce, try challenge.identityNonce())
            XCTAssertEqual(challenge.nonce.count, 64)
            let result = try await client.signIn(provider: provider, challenge: challenge.id,
                assertion: assertion(provider: provider, nonce: challenge.nonce))
            XCTAssertEqual(result.account.id, accountID)
            XCTAssertEqual(result.account.provider, provider)
            XCTAssertEqual(result.authority, .supabase)
            XCTAssertEqual(result.refreshToken, "shortToken12")
            XCTAssertNoThrow(try result.validateReceipt())
            let requests = SupabaseTestURLProtocol.requests
            XCTAssertEqual(requests.count, 2)
            XCTAssertEqual(requests[0].0.url?.absoluteString, "https://test.supabase.co/auth/v1/token?grant_type=id_token")
            XCTAssertNil(requests[0].0.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(requests[0].0.value(forHTTPHeaderField: "apikey"), publicKey)
            XCTAssertNil(requests[0].0.value(forHTTPHeaderField: "Cookie"))
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].1) as? [String: String])
            XCTAssertEqual(Set(body.keys), ["provider", "id_token", "nonce"])
            XCTAssertEqual(body["nonce"], challenge.nonce)
            XCTAssertEqual(body["provider"], provider.rawValue)
            XCTAssertEqual(requests[1].0.url?.path, "/auth/v1/user")
            XCTAssertEqual(requests[1].0.value(forHTTPHeaderField: "Authorization"), "Bearer \(jwt)")
        }
    }

    func testChallengesCannotBeReusedOrSwitchedToAnotherProvider() async throws {
        configure()
        let client = makeClient()
        let challenge = try await client.challenge(provider: .google)
        do {
            _ = try await client.signIn(provider: .apple, challenge: challenge.id, assertion: assertion(provider: .apple, nonce: challenge.nonce))
            XCTFail("Provider switch accepted")
        } catch {}
        do {
            _ = try await client.signIn(provider: .google, challenge: challenge.id, assertion: assertion(nonce: challenge.nonce))
            XCTFail("Consumed challenge accepted")
        } catch {}
        XCTAssertTrue(SupabaseTestURLProtocol.requests.isEmpty)
    }

    func testWrongNativeSubjectRejectsIdentityAndRevokesReceivedSession() async throws {
        configure(subject: "different-user")
        let client = makeClient()
        let challenge = try await client.challenge(provider: .google)
        do {
            _ = try await client.signIn(provider: .google, challenge: challenge.id, assertion: assertion(nonce: challenge.nonce))
            XCTFail("Wrong identity accepted")
        } catch AccountAccessError.invalidResponse {} catch { XCTFail("Unexpected error") }
        XCTAssertEqual(SupabaseTestURLProtocol.requests.last?.0.url?.path, "/auth/v1/logout")
    }

    func testRefreshUsesSupabaseOpaqueTokenAndPreservesSelectedProvider() async throws {
        configure(provider: .apple, includesGoogle: true)
        let result = try await makeClient().refresh(token: "shortToken12", provider: .apple)
        XCTAssertEqual(result.account.provider, .apple)
        let first = try XCTUnwrap(SupabaseTestURLProtocol.requests.first)
        XCTAssertEqual(first.0.url?.query, "grant_type=refresh_token")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: first.1) as? [String: String])
        XCTAssertEqual(body, ["refresh_token": "shortToken12"])
    }

    func testLogoutOnlyRevokesCurrentSession() async throws {
        configure()
        try await makeClient().signOut(token: jwt)
        XCTAssertEqual(SupabaseTestURLProtocol.requests.first?.0.url?.query, "scope=local")
        XCTAssertEqual(SupabaseTestURLProtocol.requests.count, 1)
    }

    func testProviderSettingsDoNotEnableFundsAndRespectAppleCapability() async throws {
        configure()
        let config = try await makeClient(appleEnabled: false).configuration()
        XCTAssertEqual(config.providers, [.google])
        XCTAssertFalse(config.depositsEnabled)
        XCTAssertFalse(config.tradingEnabled)
    }

    func testMissingWalletFunctionDoesNotReturnAnUnboundWallet() async throws {
        SupabaseTestURLProtocol.configure { _ in (404, Data("{}".utf8)) }
        do { _ = try await makeClient().wallet(token: jwt); XCTFail("Missing registry became an unbound wallet") }
        catch AccountAccessError.walletSetupRequired {} catch { XCTFail("Unexpected error") }
    }

    func testWalletUsesAuthenticatedEdgeFunctionAndValidatesSignatureShape() async throws {
        let response = try JSONSerialization.data(withJSONObject: ["accountId": accountID.uuidString, "address": NSNull()])
        SupabaseTestURLProtocol.configure { _ in (200, response) }
        let client = makeClient()
        let registration = try await client.wallet(token: jwt)
        XCTAssertNil(registration.address)
        XCTAssertEqual(SupabaseTestURLProtocol.requests.first?.0.url?.path, "/functions/v1/bsmart-wallet")
        do { _ = try await client.bindWallet(challenge: UUID(), signature: "invalid", token: jwt); XCTFail("Invalid signature sent") }
        catch {}
        XCTAssertEqual(SupabaseTestURLProtocol.requests.count, 1)
    }

    func testSupabaseSessionsHaveSeparateValidationAndLegacyDecodeIsUnchanged() throws {
        let session = TradingAccountSession(account: .init(id: accountID, provider: .google), accessToken: jwt,
            expiresAt: Date().addingTimeInterval(3600), refreshToken: "shortToken12",
            refreshExpiresAt: Date().addingTimeInterval(30 * 86400), authority: .supabase)
        XCTAssertNoThrow(try session.validateReceipt())
        XCTAssertFalse(TradingAccountSession.validToken(jwt))
        let legacy = TradingAccountSession(account: session.account, accessToken: jwt, expiresAt: session.expiresAt)
        XCTAssertThrowsError(try legacy.validateReceipt())
        let data = try BSmartJSONCoding.makeEncoder().encode(session)
        let decoded = try BSmartJSONCoding.makeDecoder().decode(TradingAccountSession.self, from: data)
        XCTAssertEqual(decoded.authority, .supabase)
        XCTAssertEqual(decoded.refreshToken, session.refreshToken)
        XCTAssertEqual(String(reflecting: decoded), "TradingAccountSession(redacted)")
    }

    @MainActor
    func testGoogleLoginKeychainRestoreAndLogoutNeverRequireWalletOrResearchAPI() async throws {
        configure()
        let storage = KeychainAccountSessionStore(service: "bsmart.tests.google." + UUID().uuidString)
        defer { try? storage.clear() }
        let store = AccountAccessStore(client: makeClient(appleEnabled: false), storage: storage)
        await store.load()
        XCTAssertNil(store.identity)
        await store.signIn(.google) { challenge in self.assertion(nonce: challenge.nonce) }
        XCTAssertEqual(store.identity?.id, accountID)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(try storage.load()?.authority, .supabase)

        let reopened = AccountAccessStore(client: makeClient(appleEnabled: false), storage: storage)
        await reopened.load()
        XCTAssertEqual(reopened.identity, store.identity)
        XCTAssertNil(reopened.errorMessage)
        await reopened.signOut()
        XCTAssertNil(reopened.identity)
        XCTAssertNil(try storage.load())
        let requests = SupabaseTestURLProtocol.requests
        XCTAssertEqual(requests.count, 6)
        XCTAssertTrue(requests.allSatisfy { $0.0.url?.host == "test.supabase.co" && $0.0.url?.path.hasPrefix("/auth/v1/") == true })
    }

    @MainActor
    func testSupabaseOfflineLogoutClearsSessionAndInvalidatesSigningLease() async throws {
        let userData = try JSONSerialization.data(withJSONObject: ["id": accountID.uuidString,
            "identities": [["provider": "google", "identity_data": ["sub": "native-subject"]]]])
        SupabaseTestURLProtocol.configure { request in
            if request.url?.path == "/auth/v1/settings" { return (200, Data(#"{"external":{"google":true}}"#.utf8)) }
            if request.url?.path == "/auth/v1/logout" { return (503, Data("{}".utf8)) }
            return (200, userData)
        }
        let saved = TradingAccountSession(account: .init(id: accountID, provider: .google), accessToken: jwt,
            expiresAt: Date().addingTimeInterval(3600), refreshToken: "shortToken12",
            refreshExpiresAt: Date().addingTimeInterval(30 * 86400), authority: .supabase)
        let storage = RenewalMemoryStorage(saved)
        let store = AccountAccessStore(client: makeClient(), storage: storage)
        await store.load()
        XCTAssertEqual(store.identity, saved.account)
        let wallet = DeviceWalletSummary(accountID: accountID, address: "0x" + String(repeating: "1", count: 40), recoveryVerified: true)
        let lease = try store.fundingSigningLease(wallet: wallet)
        await store.signOut()
        XCTAssertNil(storage.saved)
        XCTAssertNil(store.identity)
        XCTAssertNil(store.walletAccountID)
        XCTAssertThrowsError(try lease.check(wallet: wallet))
        XCTAssertNotNil(store.errorMessage)
    }

    @MainActor
    func testExpiredSupabaseAccessRotatesAndRestoresUsingShortRefreshToken() async throws {
        configure()
        let previous = TradingAccountSession(account: .init(id: accountID, provider: .google), accessToken: jwt + "Old",
            expiresAt: Date().addingTimeInterval(-10), refreshToken: "previousShort12",
            refreshExpiresAt: Date().addingTimeInterval(86400), authority: .supabase)
        let storage = RenewalMemoryStorage(previous)
        let store = AccountAccessStore(client: makeClient(), storage: storage)
        await store.load()
        XCTAssertEqual(store.identity, previous.account)
        XCTAssertEqual(storage.saved?.accessToken, jwt)
        XCTAssertEqual(storage.saved?.refreshToken, "shortToken12")
        XCTAssertFalse(storage.pending)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testRefreshOutageKeepsIdentityAndRetriesPendingRotationAfterRecovery() async throws {
        let previous = TradingAccountSession(account: .init(id: accountID, provider: .google), accessToken: jwt + "Old",
            expiresAt: Date().addingTimeInterval(-10), refreshToken: "previousShort12",
            refreshExpiresAt: Date().addingTimeInterval(86400), authority: .supabase)
        let storage = RenewalMemoryStorage(previous)
        let store = AccountAccessStore(client: makeClient(), storage: storage)
        SupabaseTestURLProtocol.configure { _ in (503, Data("{}".utf8)) }
        await store.load()
        XCTAssertEqual(store.identity, previous.account)
        XCTAssertEqual(storage.saved, previous)
        XCTAssertTrue(storage.pending)
        XCTAssertNil(store.walletAccountID, "Expired identity must not authorize wallet operations")
        configure()
        let value: String = try await store.withFeedSession { _ in "recovered" }
        XCTAssertEqual(value, "recovered")
        XCTAssertEqual(storage.saved?.accessToken, jwt)
        XCTAssertFalse(storage.pending)
        XCTAssertFalse(SupabaseTestURLProtocol.requests.contains { $0.0.url?.path == "/auth/v1/logout" })
    }

    @MainActor
    func testColdStartRecoversPendingSupabaseRotationInsteadOfRevokingIt() async throws {
        configure()
        let previous = TradingAccountSession(account: .init(id: accountID, provider: .google), accessToken: jwt + "Old",
            expiresAt: Date().addingTimeInterval(30), refreshToken: "previousShort12",
            refreshExpiresAt: Date().addingTimeInterval(86400), authority: .supabase)
        let storage = RenewalMemoryStorage(previous)
        try storage.beginRenewal(previous)
        let store = AccountAccessStore(client: makeClient(), storage: storage)
        await store.load()
        XCTAssertEqual(store.identity, previous.account)
        XCTAssertFalse(storage.pending)
        XCTAssertEqual(storage.saved?.accessToken, jwt)
        XCTAssertFalse(SupabaseTestURLProtocol.requests.contains { $0.0.url?.path == "/auth/v1/logout" })
    }

    @MainActor
    func testKeychainLockDuringRotationDoesNotRevokeGoogleSession() async throws {
        configure()
        let previous = TradingAccountSession(account: .init(id: accountID, provider: .google), accessToken: jwt + "Old",
            expiresAt: Date().addingTimeInterval(-10), refreshToken: "previousShort12",
            refreshExpiresAt: Date().addingTimeInterval(86400), authority: .supabase)
        let storage = RenewalMemoryStorage(previous)
        storage.rejectsSave = true
        let store = AccountAccessStore(client: makeClient(), storage: storage)
        await store.load()
        XCTAssertEqual(store.identity, previous.account)
        XCTAssertTrue(storage.pending)
        XCTAssertFalse(SupabaseTestURLProtocol.requests.contains { $0.0.url?.path == "/auth/v1/logout" })
        storage.rejectsSave = false
        let value: Bool = try await store.withFeedSession { _ in true }
        XCTAssertTrue(value)
        XCTAssertFalse(storage.pending)
    }

    @MainActor
    func testExplicitRefreshRejectionClearsSessionButServerErrorsDoNot() async throws {
        let previous = TradingAccountSession(account: .init(id: accountID, provider: .google), accessToken: jwt + "Old",
            expiresAt: Date().addingTimeInterval(-10), refreshToken: "previousShort12",
            refreshExpiresAt: Date().addingTimeInterval(86400), authority: .supabase)
        let storage = RenewalMemoryStorage(previous)
        SupabaseTestURLProtocol.configure { _ in (400, Data(#"{"error_code":"refresh_token_not_found"}"#.utf8)) }
        let store = AccountAccessStore(client: makeClient(), storage: storage)
        await store.load()
        XCTAssertNil(store.identity)
        XCTAssertNil(storage.saved)
    }

    @MainActor
    func testOfflineForegroundReloadDoesNotRemoveGoogleIdentity() async throws {
        configure()
        let saved = TradingAccountSession(account: .init(id: accountID, provider: .google), accessToken: jwt,
            expiresAt: Date().addingTimeInterval(3600), refreshToken: "shortToken12",
            refreshExpiresAt: Date().addingTimeInterval(86400), authority: .supabase)
        let storage = RenewalMemoryStorage(saved)
        let store = AccountAccessStore(client: makeClient(), storage: storage)
        await store.load()
        SupabaseTestURLProtocol.configure { _ in (503, Data("{}".utf8)) }
        await store.load()
        XCTAssertEqual(store.identity, saved.account)
        XCTAssertEqual(storage.saved, saved)
        XCTAssertFalse(store.configuration.tradingEnabled)
    }

    func testTokenShapeAndSessionAuthorityCannotBeConfused() throws {
        for token in ["", "header..signature", "a.b.c", jwt + "\n", jwt + ".extra"] {
            XCTAssertFalse(TradingAccountSession.validSupabaseAccessToken(token))
        }
        XCTAssertFalse(TradingAccountSession.validSupabaseRefreshToken("short"))
        let legacy = renewalSession(account: .init(id: accountID, provider: .google))
        let replacement = TradingAccountSession(account: legacy.account, accessToken: jwt,
            expiresAt: Date().addingTimeInterval(3600), refreshToken: "shortToken12",
            refreshExpiresAt: Date().addingTimeInterval(86400), authority: .supabase)
        XCTAssertThrowsError(try replacement.validateRenewal(of: legacy))
    }

    private func makeClient(appleEnabled: Bool = true) -> SupabaseAccountAuthClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SupabaseTestURLProtocol.self]
        config.httpAdditionalHeaders = ["Authorization": "old-api-token", "Cookie": "old-cookie"]
        return .init(configuration: SupabaseAccountConfiguration(url: "https://test.supabase.co", publishableKey: publicKey,
            appleEnabled: appleEnabled)!, sessionConfiguration: config)
    }

    private func assertion(provider: AccountIdentityProvider = .google, nonce: String) -> AccountIdentityAssertion {
        .init(idToken: String(repeating: "disposable-id-token-", count: 3),
              authorizationCode: provider == .apple ? String(repeating: "disposable-code-", count: 3) : nil,
              appleUserID: provider == .apple ? "native-subject" : nil,
              googleUserID: provider == .google ? "native-subject" : nil, nonce: nonce)
    }

    @MainActor
    func testOnlyCurrentVerifiedBoundWalletEnablesCapabilitiesAndLogoutClosesThem() async throws {
        let registration = TradingWalletRegistration(accountId: accountID, address: "0x" + String(repeating: "1", count: 40),
            capabilities: .init(depositsEnabled: true, tradingEnabled: true, withdrawalsEnabled: false))
        configure(wallet: registration)
        let storage = RenewalMemoryStorage(nil)
        let store = AccountAccessStore(client: makeClient(), storage: storage)
        await store.load()
        await store.signIn(.google) { self.assertion(nonce: $0.nonce) }
        XCTAssertFalse(store.configuration.tradingEnabled)
        _ = try await store.walletRegistration()
        XCTAssertTrue(store.configuration.depositsEnabled)
        XCTAssertTrue(store.configuration.tradingEnabled)
        XCTAssertEqual(store.configuration.withdrawalsEnabled, false)
        await store.signOut()
        XCTAssertFalse(store.configuration.depositsEnabled)
        XCTAssertFalse(store.configuration.tradingEnabled)
        XCTAssertEqual(store.configuration.withdrawalsEnabled, false)
    }

    @MainActor
    func testMissingCapabilitiesUnboundWalletAndFailedRegistryFailClosedWithoutLoggingOut() async throws {
        let address = "0x" + String(repeating: "1", count: 40)
        let open = TradingWalletCapabilities(depositsEnabled: true, tradingEnabled: true, withdrawalsEnabled: true)
        configure(wallet: .init(accountId: accountID, address: address, capabilities: open))
        let store = AccountAccessStore(client: makeClient(), storage: RenewalMemoryStorage(nil))
        await store.load()
        await store.signIn(.google) { self.assertion(nonce: $0.nonce) }
        _ = try await store.walletRegistration()
        XCTAssertTrue(store.configuration.tradingEnabled)
        for registration in [TradingWalletRegistration(accountId: accountID, address: nil, capabilities: open),
                             .init(accountId: accountID, address: address)] {
            configure(wallet: registration)
            _ = try await store.walletRegistration()
            XCTAssertFalse(store.configuration.tradingEnabled)
            XCTAssertNotNil(store.identity)
        }
        configure(wallet: .init(accountId: UUID(), address: address, capabilities: open))
        do { _ = try await store.walletRegistration(); XCTFail("Other account accepted") } catch {}
        XCTAssertFalse(store.configuration.depositsEnabled)
        XCTAssertNotNil(store.identity)
        SupabaseTestURLProtocol.configure { _ in (503, Data("{}".utf8)) }
        do { _ = try await store.walletRegistration(); XCTFail("Registry outage accepted") } catch {}
        XCTAssertFalse(store.configuration.tradingEnabled)
        XCTAssertNotNil(store.identity)
    }

    private func configure(provider: AccountIdentityProvider = .google, subject: String = "native-subject", includesGoogle: Bool = false,
                           wallet: TradingWalletRegistration? = nil) {
        var identities: [[String: Any]] = [["provider": provider.rawValue, "identity_data": ["sub": subject]]]
        if includesGoogle { identities.insert(["provider": "google", "identity_data": ["sub": "linked-google"]], at: 0) }
        let user: [String: Any] = ["id": accountID.uuidString, "identities": identities]
        let session: [String: Any] = ["access_token": jwt, "refresh_token": "shortToken12", "token_type": "bearer",
                                     "expires_in": 3600, "user": user]
        let userData = try! JSONSerialization.data(withJSONObject: user)
        let sessionData = try! JSONSerialization.data(withJSONObject: session)
        let walletData = try? JSONEncoder().encode(wallet)
        SupabaseTestURLProtocol.configure { request in
            if request.url?.path == "/functions/v1/bsmart-wallet", let walletData { return (200, walletData) }
            if request.url?.path == "/auth/v1/logout" { return (204, Data()) }
            if request.url?.path == "/auth/v1/settings" { return (200, Data(#"{"external":{"apple":true,"google":true}}"#.utf8)) }
            return (200, request.url?.path == "/auth/v1/user" ? userData : sessionData)
        }
    }
}

private final class SupabaseTestURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var handler: ((URLRequest) -> (Int, Data))?
    private static var captured: [(URLRequest, Data)] = []
    static var requests: [(URLRequest, Data)] { lock.withLock { captured } }
    static func configure(_ value: @escaping (URLRequest) -> (Int, Data)) {
        lock.withLock { handler = value; captured = [] }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let result = Self.lock.withLock { Self.captured.append((request, body)); return Self.handler!(request) }
        let response = HTTPURLResponse(url: request.url!, statusCode: result.0, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
