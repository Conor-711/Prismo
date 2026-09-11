import Foundation

protocol AccountAuthenticating: Sendable {
    func configuration() async throws -> AccountAuthConfiguration
    func challenge(provider: AccountIdentityProvider) async throws -> AccountAuthChallenge
    func signIn(provider: AccountIdentityProvider, challenge: UUID, assertion: AccountIdentityAssertion) async throws -> TradingAccountSession
    func reauthenticate(account: TradingAccountIdentity, challenge: UUID, assertion: AccountIdentityAssertion) async throws -> TradingAccountSession
    func account(token: String) async throws -> TradingAccountIdentity
    func account(token: String, provider: AccountIdentityProvider) async throws -> TradingAccountIdentity
    func signOut(token: String) async throws
    func refresh(token: String) async throws -> TradingAccountSession
    func refresh(token: String, provider: AccountIdentityProvider) async throws -> TradingAccountSession
    func revokeRefresh(token: String) async throws
    func wallet(token: String) async throws -> TradingWalletRegistration
    func walletChallenge(address: String, token: String) async throws -> TradingWalletChallenge
    func bindWallet(challenge: UUID, signature: String, token: String) async throws -> TradingWalletRegistration
}

extension AccountAuthenticating {
    func account(token: String, provider: AccountIdentityProvider) async throws -> TradingAccountIdentity {
        try await account(token: token)
    }
    func refresh(token: String, provider: AccountIdentityProvider) async throws -> TradingAccountSession {
        try await refresh(token: token)
    }
    func revoke(session: TradingAccountSession) async throws {
        if session.authority == .supabase || session.refreshToken == nil {
            try await signOut(token: session.accessToken)
        } else if let token = session.refreshToken {
            try await revokeRefresh(token: token)
        }
    }
    func reauthenticate(account: TradingAccountIdentity, challenge: UUID, assertion: AccountIdentityAssertion) async throws -> TradingAccountSession {
        throw AccountAccessError.unavailable
    }
    func refresh(token: String) async throws -> TradingAccountSession { throw AccountAccessError.unavailable }
    func revokeRefresh(token: String) async throws { throw AccountAccessError.unavailable }
    func wallet(token: String) async throws -> TradingWalletRegistration { throw AccountAccessError.unavailable }
    func walletChallenge(address: String, token: String) async throws -> TradingWalletChallenge { throw AccountAccessError.unavailable }
    func bindWallet(challenge: UUID, signature: String, token: String) async throws -> TradingWalletRegistration {
        throw AccountAccessError.unavailable
    }
}

final class HTTPAccountAuthClient: AccountAuthenticating, @unchecked Sendable {
    private let baseURL: URL
    private let authorization: BSmartAuthorizationProviding
    private let session: URLSession

    init(baseURL: URL, authorization: BSmartAuthorizationProviding, configuration: URLSessionConfiguration = .ephemeral) {
        self.baseURL = baseURL
        self.authorization = authorization
        let config = configuration.copy() as! URLSessionConfiguration
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.httpAdditionalHeaders = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config, delegate: NoAccountRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func configuration() async throws -> AccountAuthConfiguration {
        try await get("configuration", token: nil)
    }

    func challenge(provider: AccountIdentityProvider) async throws -> AccountAuthChallenge {
        struct Input: Encodable { let provider: AccountIdentityProvider }
        let token = try await authorization.accessToken()
        return try await send("challenges", method: "POST", body: Input(provider: provider), token: token)
    }

    func signIn(provider: AccountIdentityProvider, challenge: UUID, assertion: AccountIdentityAssertion) async throws -> TradingAccountSession {
        try await exchange(provider: provider, challenge: challenge, assertion: assertion, expectedAccountID: nil)
    }

    func reauthenticate(account: TradingAccountIdentity, challenge: UUID, assertion: AccountIdentityAssertion) async throws -> TradingAccountSession {
        try await exchange(provider: account.provider, challenge: challenge, assertion: assertion, expectedAccountID: account.id)
    }

    private func exchange(provider: AccountIdentityProvider, challenge: UUID, assertion: AccountIdentityAssertion,
                          expectedAccountID: UUID?) async throws -> TradingAccountSession {
        try assertion.validate(for: provider)
        struct Input: Encodable {
            let provider: AccountIdentityProvider; let challengeId: UUID; let idToken: String; let authorizationCode: String?
            let expectedAccountId: UUID?
            let nonce: String?
        }
        let token = try await authorization.accessToken()
        return try await send("sessions", method: "POST",
            body: Input(provider: provider, challengeId: challenge, idToken: assertion.idToken,
                        authorizationCode: assertion.authorizationCode, expectedAccountId: expectedAccountID,
                        nonce: assertion.nonce), token: token)
    }

    func account(token: String) async throws -> TradingAccountIdentity {
        try await get("account", token: token)
    }

    func signOut(token: String) async throws {
        _ = try await request("sessions/current", method: "DELETE", body: nil, token: token, expectedStatus: 204)
    }

    func refresh(token: String) async throws -> TradingAccountSession {
        guard TradingAccountSession.validToken(token) else { throw AccountAccessError.invalidResponse }
        struct Input: Encodable { let refreshToken: String }
        let installation = try await authorization.accessToken()
        return try await send("sessions/refresh", method: "POST", body: Input(refreshToken: token), token: installation)
    }

    func revokeRefresh(token: String) async throws {
        guard TradingAccountSession.validToken(token) else { throw AccountAccessError.invalidResponse }
        struct Input: Encodable { let refreshToken: String }
        let installation = try await authorization.accessToken()
        _ = try await request("sessions/revoke", method: "POST", body: JSONEncoder().encode(Input(refreshToken: token)),
                              token: installation, expectedStatus: 204)
    }

    func wallet(token: String) async throws -> TradingWalletRegistration { try await get("wallet", token: token) }

    func walletChallenge(address: String, token: String) async throws -> TradingWalletChallenge {
        struct Input: Encodable { let address: String }
        return try await send("wallet/challenges", method: "POST", body: Input(address: address), token: token)
    }

    func bindWallet(challenge: UUID, signature: String, token: String) async throws -> TradingWalletRegistration {
        struct Input: Encodable { let challengeId: UUID; let signature: String }
        return try await send("wallet", method: "PUT", body: Input(challengeId: challenge, signature: signature), token: token)
    }

    private func get<T: Decodable>(_ path: String, token: String?) async throws -> T {
        let data = try await request(path, method: "GET", body: nil, token: token)
        return try BSmartJSONCoding.makeDecoder().decode(T.self, from: data)
    }

    private func send<T: Decodable, Body: Encodable>(_ path: String, method: String, body: Body, token: String) async throws -> T {
        let data = try await request(path, method: method, body: JSONEncoder().encode(body), token: token)
        return try BSmartJSONCoding.makeDecoder().decode(T.self, from: data)
    }

    func installationAccessToken() async throws -> String { try await authorization.accessToken() }

    var accountDeletionEndpoint: URL { baseURL.appending(path: "v1/auth/account/deletions") }

    func request(_ path: String, method: String, body: Data?, token: String?, expectedStatus: Int = 200,
                 statusErrors: [Int: Error] = [:]) async throws -> Data {
        // Identity assertions must never be posted to the HTTP research development server.
        guard baseURL.scheme == "https", baseURL.host != nil, baseURL.user == nil,
              baseURL.password == nil, baseURL.query == nil, baseURL.fragment == nil else {
            throw AccountAccessError.unavailable
        }
        var request = URLRequest(url: baseURL.appending(path: "v1/auth/\(path)"))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, http.url == request.url,
              response.expectedContentLength <= 65536 else {
            throw AccountAccessError.invalidResponse
        }
        if let error = statusErrors[http.statusCode] { throw error }
        if http.statusCode == 401 { throw AccountAccessError.expired }
        if http.statusCode == 409 { throw DeviceWalletError.recoveryRequired }
        if [404, 429, 503].contains(http.statusCode) { throw AccountAccessError.unavailable }
        guard http.statusCode == expectedStatus else { throw AccountAccessError.invalidResponse }
        guard http.statusCode == 204 || http.mimeType == "application/json" else { throw AccountAccessError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 65536 else { throw AccountAccessError.invalidResponse }
            data.append(byte)
        }
        return data
    }
}

private final class NoAccountRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
