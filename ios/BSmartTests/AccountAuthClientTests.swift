import XCTest
@testable import BSmart

final class AccountAuthClientTests: XCTestCase {
    private let idToken = String(repeating: "disposable-id-token-", count: 4)
    private let code = String(repeating: "disposable-apple-code-", count: 3)

    func testSupabaseChallengeUsesHashedNonceButExchangeCarriesOriginalNonce() async throws {
        let raw = "disposable-installation-challenge-123456"
        let hashed = "1fc2ecc995d378537bdc2112c00721852b9a3cd3d80551eba14e66096a1a8d6f"
        let challenge = AccountAuthChallenge(id: UUID(), nonce: raw, expiresAt: Date().addingTimeInterval(300),
                                             providerNonce: hashed)
        XCTAssertEqual(try challenge.identityNonce(), hashed)
        AccountExchangeURLProtocol.configure(data: response(provider: .google))
        _ = try await makeClient().signIn(provider: .google, challenge: challenge.id,
            assertion: .init(idToken: idToken, authorizationCode: nil, nonce: raw))
        let capture = try XCTUnwrap(AccountExchangeURLProtocol.captured)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: capture.1) as? [String: String])
        XCTAssertEqual(body["nonce"], raw)
        XCTAssertNil(body["providerNonce"])
        XCTAssertNil(body["authorizationCode"])
        XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 1)
    }

    func testChallengeSupportsLegacyButRejectsMismatchedHash() throws {
        let id = UUID()
        let raw = "disposable-installation-challenge-123456"
        XCTAssertEqual(try AccountAuthChallenge(id: id, nonce: raw, expiresAt: Date()).identityNonce(), raw)
        let json = Data("""
        {"id":"\(id.uuidString)","nonce":"\(raw)","expiresAt":"2099-01-01T00:00:00Z"}
        """.utf8)
        let legacy = try BSmartJSONCoding.makeDecoder().decode(AccountAuthChallenge.self, from: json)
        XCTAssertNil(legacy.providerNonce)
        XCTAssertEqual(try legacy.identityNonce(), raw)
        let bad = AccountAuthChallenge(id: id, nonce: raw, expiresAt: Date(), providerNonce: "wrong-hash")
        XCTAssertThrowsError(try bad.identityNonce())
    }

    func testInvalidSupabaseNonceIsNotSentOrLogged() async {
        for raw in ["short", String(repeating: "x", count: 129), String(repeating: "n", count: 32) + "\n"] {
            AccountExchangeURLProtocol.configure(data: response(provider: .google))
            let assertion = AccountIdentityAssertion(idToken: idToken, authorizationCode: nil, nonce: raw)
            XCTAssertEqual(String(reflecting: assertion), "AccountIdentityAssertion(redacted)")
            do { _ = try await makeClient().signIn(provider: .google, challenge: UUID(), assertion: assertion)
                XCTFail("Invalid nonce sent")
            } catch AccountAccessError.invalidResponse {} catch { XCTFail("Unexpected error") }
            XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 0)
        }
    }

    func testAppleRequestIncludesCodeWhileGoogleOmitsIt() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AccountExchangeURLProtocol.self]
        config.httpAdditionalHeaders = ["Authorization": "old-session", "Cookie": "private", "X-Secret": "private"]
        let client = HTTPAccountAuthClient(baseURL: URL(string: "https://account.example.invalid")!,
                                          authorization: ExchangeInstallationAuthorization(), configuration: config)
        for provider in AccountIdentityProvider.allCases {
            let challenge = UUID()
            let assertion = AccountIdentityAssertion(idToken: idToken, authorizationCode: provider == .apple ? code : nil,
                appleUserID: provider == .apple ? "opaque-local-apple-user" : nil)
            AccountExchangeURLProtocol.configure(data: response(provider: provider))
            let session = try await client.signIn(provider: provider, challenge: challenge, assertion: assertion)
            XCTAssertEqual(session.account.provider, provider)
            let capture = try XCTUnwrap(AccountExchangeURLProtocol.captured)
            XCTAssertEqual(capture.0.url?.absoluteString, "https://account.example.invalid/v1/auth/sessions")
            XCTAssertEqual(capture.0.httpMethod, "POST")
            XCTAssertEqual(capture.0.value(forHTTPHeaderField: "Authorization"), "Bearer disposable-installation-token")
            XCTAssertEqual(capture.0.value(forHTTPHeaderField: "Cache-Control"), "no-store")
            XCTAssertNil(capture.0.value(forHTTPHeaderField: "Cookie"))
            XCTAssertNil(capture.0.value(forHTTPHeaderField: "X-Secret"))
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: capture.1) as? [String: String])
            var expected = ["provider": provider.rawValue, "challengeId": challenge.uuidString, "idToken": idToken]
            if provider == .apple { expected["authorizationCode"] = code }
            XCTAssertEqual(body, expected)
            XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 1)
        }
        XCTAssertNotNil(config.httpAdditionalHeaders?["X-Secret"])
    }

    func testInvalidAssertionsAreRejectedBeforeAnyRequest() async {
        let client = makeClient()
        for (provider, assertion) in [
            (AccountIdentityProvider.apple, AccountIdentityAssertion(idToken: idToken, authorizationCode: nil)),
            (.apple, .init(idToken: idToken, authorizationCode: String(repeating: "c", count: 31))),
            (.apple, .init(idToken: idToken, authorizationCode: String(repeating: "c", count: 2049))),
            (.apple, .init(idToken: idToken, authorizationCode: code + "\n")),
            (.apple, .init(idToken: idToken, authorizationCode: code + " ")),
            (.google, .init(idToken: idToken, authorizationCode: code)),
            (.google, .init(idToken: idToken, authorizationCode: nil, appleUserID: "wrong-provider")),
            (.apple, .init(idToken: idToken, authorizationCode: code, appleUserID: "")),
            (.google, .init(idToken: String(repeating: "t", count: 16385), authorizationCode: nil)),
            (.google, .init(idToken: "short", authorizationCode: nil))
        ] {
            AccountExchangeURLProtocol.configure(data: response(provider: provider))
            do {
                _ = try await client.signIn(provider: provider, challenge: UUID(), assertion: assertion)
                XCTFail("Invalid assertion accepted")
            } catch AccountAccessError.invalidResponse {} catch { XCTFail("Unexpected error type") }
            XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 0)
        }
    }

    func testDeletionReauthenticationSendsExpectedAccountAndNoLocalProviderReference() async throws {
        for provider in AccountIdentityProvider.allCases {
            let account = TradingAccountIdentity(id: UUID(), provider: provider)
            let challenge = UUID()
            let assertion = AccountIdentityAssertion(idToken: idToken, authorizationCode: provider == .apple ? code : nil,
                appleUserID: provider == .apple ? "local-apple" : nil, googleUserID: provider == .google ? "local-google" : nil)
            AccountExchangeURLProtocol.configure(data: response(provider: provider))
            _ = try await makeClient().reauthenticate(account: account, challenge: challenge, assertion: assertion)
            let capture = try XCTUnwrap(AccountExchangeURLProtocol.captured)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: capture.1) as? [String: String])
            var expected = ["provider": provider.rawValue, "challengeId": challenge.uuidString,
                            "idToken": idToken, "expectedAccountId": account.id.uuidString]
            if provider == .apple { expected["authorizationCode"] = code }
            XCTAssertEqual(body, expected)
            XCTAssertEqual(capture.0.url?.path, "/v1/auth/sessions")
            XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 1)
        }
    }

    func testRefreshAndRevokeUseOnlyInstallationAuthorizationAndBodyCredential() async throws {
        let client = makeClient()
        let token = "bsr_" + String(repeating: "disposable", count: 8)
        AccountExchangeURLProtocol.configure(data: response())
        _ = try await client.refresh(token: token)
        try assertRenewalRequest(path: "refresh", token: token)
        AccountExchangeURLProtocol.configure(status: 204, data: Data())
        try await client.revokeRefresh(token: token)
        try assertRenewalRequest(path: "revoke", token: token)
    }

    func testInvalidRefreshCredentialsNeverReachTransport() async {
        let client = makeClient()
        for token in ["short", String(repeating: "x", count: 257), String(repeating: "x", count: 40) + "\n"] {
            AccountExchangeURLProtocol.configure(data: response())
            do { _ = try await client.refresh(token: token); XCTFail("Invalid refresh sent") } catch {}
            do { try await client.revokeRefresh(token: token); XCTFail("Invalid revocation sent") } catch {}
            XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 0)
        }
    }

    func testRefreshFailureIsNotRetriedOrExposedInError() async {
        let client = makeClient()
        let token = "bsr_" + String(repeating: "disposable", count: 8)
        for status in [302, 401, 429, 503] {
            AccountExchangeURLProtocol.configure(status: status, data: Data(token.utf8))
            do { _ = try await client.refresh(token: token); XCTFail("Failed renewal accepted") }
            catch { XCTAssertFalse(error.localizedDescription.contains(token)) }
            XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 1)
        }
    }

    func testLogoutRequiresExact204NotAnUnexpectedSuccessPayload() async {
        let client = makeClient()
        let token = "bsr_" + String(repeating: "disposable", count: 8)
        for status in [200, 202, 401, 503] {
            AccountExchangeURLProtocol.configure(status: status, data: Data("{\"error\":\"unavailable\"}".utf8))
            do { try await client.revokeRefresh(token: token); XCTFail("Logout acknowledged without 204") } catch {}
            XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 1)
        }
    }

    private func assertRenewalRequest(path: String, token: String) throws {
        let capture = try XCTUnwrap(AccountExchangeURLProtocol.captured)
        XCTAssertEqual(capture.0.url?.absoluteString, "https://account.example.invalid/v1/auth/sessions/\(path)")
        XCTAssertEqual(capture.0.httpMethod, "POST")
        XCTAssertEqual(capture.0.value(forHTTPHeaderField: "Authorization"), "Bearer disposable-installation-token")
        XCTAssertEqual(capture.0.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: capture.1) as? [String: String])
        XCTAssertEqual(body, ["refreshToken": token])
        XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 1)
    }

    func testAssertionsAreRedactedWhenFormattedForDiagnostics() {
        let assertion = AccountIdentityAssertion(idToken: idToken, authorizationCode: code, appleUserID: "opaque-local-apple-user")
        for description in [String(describing: assertion), String(reflecting: assertion), "\(assertion)"] {
            XCTAssertEqual(description, "AccountIdentityAssertion(redacted)")
            XCTAssertFalse(description.contains(idToken))
            XCTAssertFalse(description.contains(code))
            XCTAssertFalse(description.contains("opaque-local-apple-user"))
        }
    }

    func testInvalidServerResponsesCannotReturnSessionOrLeakCode() async {
        let client = makeClient()
        let assertion = AccountIdentityAssertion(idToken: idToken, authorizationCode: code)
        for (status, mime, bytes, url) in [
            (302, "application/json", response(), nil), (401, "application/json", Data(code.utf8), nil),
            (429, "application/json", Data(code.utf8), nil), (503, "application/json", Data(code.utf8), nil),
            (200, "text/html", response(), nil), (200, "application/json", Data(repeating: 32, count: 65537), nil),
            (200, "application/json", response(), URL(string: "https://wrong.example.invalid/v1/auth/sessions"))
        ] {
            AccountExchangeURLProtocol.configure(status: status, mime: mime, data: bytes, url: url)
            do {
                _ = try await client.signIn(provider: .apple, challenge: UUID(), assertion: assertion)
                XCTFail("Invalid response returned a session")
            } catch {
                XCTAssertTrue(error is AccountAccessError)
                XCTAssertFalse(error.localizedDescription.contains(code))
                XCTAssertFalse(error.localizedDescription.contains(idToken))
            }
            XCTAssertEqual(AccountExchangeURLProtocol.requestCount, 1)
        }
    }

    private func makeClient() -> HTTPAccountAuthClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AccountExchangeURLProtocol.self]
        return .init(baseURL: URL(string: "https://account.example.invalid")!,
                     authorization: ExchangeInstallationAuthorization(), configuration: config)
    }

    private func response(provider: AccountIdentityProvider = .apple) -> Data {
        Data("""
        {"account":{"id":"00000000-0000-0000-0000-000000000001","provider":"\(provider.rawValue)"},
        "accessToken":"disposable-account-token-not-a-provider-token","expiresAt":"2099-01-01T00:00:00Z"}
        """.utf8)
    }
}

struct ExchangeInstallationAuthorization: BSmartAuthorizationProviding {
    func accessToken() async throws -> String { "disposable-installation-token" }
    func invalidate() async {}
}

final class AccountExchangeURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var response = (status: 200, mime: "application/json", data: Data(), url: Optional<URL>.none)
    private static var copy: (URLRequest, Data)?
    private static var count = 0
    static var captured: (URLRequest, Data)? { lock.withLock { copy } }
    static var requestCount: Int { lock.withLock { count } }
    static func configure(status: Int = 200, mime: String = "application/json", data: Data, url: URL? = nil) {
        lock.withLock { response = (status, mime, data, url); copy = nil; count = 0 }
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
        let response = Self.lock.withLock { Self.copy = (request, body); Self.count += 1; return Self.response }
        let http = HTTPURLResponse(url: response.url ?? request.url!, statusCode: response.status, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": response.mime])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
