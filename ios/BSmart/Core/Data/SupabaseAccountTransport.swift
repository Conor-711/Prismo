import Foundation

struct SupabaseAccountConfiguration {
    let url: URL
    let publishableKey: String
    let appleEnabled: Bool

    init?(url: String, publishableKey: String, appleEnabled: Bool = true) {
        guard let parsed = URL(string: url), parsed.scheme == "https",
              let host = parsed.host, host.range(of: #"^[a-z0-9-]+\.supabase\.co$"#, options: .regularExpression) != nil,
              parsed.port == nil, parsed.user == nil, parsed.password == nil,
              parsed.query == nil, parsed.fragment == nil, ["", "/"].contains(parsed.path),
              publishableKey.hasPrefix("sb_publishable_"), (24...256).contains(publishableKey.utf8.count),
              publishableKey.utf8.allSatisfy({ (33...126).contains($0) }) else { return nil }
        self.url = parsed; self.publishableKey = publishableKey; self.appleEnabled = appleEnabled
    }

    static func resolve(bundle: Bundle = .main) -> Self? {
        guard let url = bundle.object(forInfoDictionaryKey: "BSMART_SUPABASE_URL") as? String,
              let key = bundle.object(forInfoDictionaryKey: "BSMART_SUPABASE_PUBLISHABLE_KEY") as? String else { return nil }
        return Self(url: url, publishableKey: key,
                    appleEnabled: bundle.object(forInfoDictionaryKey: "BSMART_APPLE_SIGN_IN_ENABLED") as? String == "YES")
    }

    var sessionNamespace: String { "supabase.\(url.host!).v1" }
}

final class SupabaseAccountTransport: @unchecked Sendable {
    private let configuration: SupabaseAccountConfiguration
    private let session: URLSession

    init(configuration: SupabaseAccountConfiguration, sessionConfiguration: URLSessionConfiguration = .ephemeral,
         requestTimeout: TimeInterval = 15, resourceTimeout: TimeInterval = 30) {
        self.configuration = configuration
        let config = sessionConfiguration.copy() as! URLSessionConfiguration
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.httpAdditionalHeaders = nil
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        session = URLSession(configuration: config, delegate: SupabaseNoRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func request(_ path: String, method: String = "GET", query: [URLQueryItem] = [],
                 body: Data? = nil, token: String? = nil, expectedStatus: Int = 200) async throws -> Data {
        var components = URLComponents(url: configuration.url.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let token {
            guard TradingAccountSession.validSupabaseAccessToken(token) else { throw AccountAccessError.expired }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        let maximumBytes = path.hasPrefix("functions/v1/bsmart-feed") ? 2_097_152
            : path.hasPrefix("functions/v1/bsmart-content/") || path.hasPrefix("functions/v1/bsmart-social") ? 524288 : 131072
        guard let http = response as? HTTPURLResponse, http.url == request.url,
              response.expectedContentLength <= maximumBytes else { throw AccountAccessError.invalidResponse }
        if http.statusCode == 401 { throw AccountAccessError.expired }
        if path.hasPrefix("functions/v1/bsmart-social/chat/") {
            if http.statusCode == 429 { throw SocialChatError.rateLimited }
            if http.statusCode == 422 { throw SocialChatError.invalidMessage }
        }
        if path == "functions/v1/bsmart-feed/orders", http.statusCode != expectedStatus {
            guard http.mimeType == "application/json" else { throw OpinionLinkError.unavailable }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 4096 else { throw OpinionLinkError.unavailable }
                data.append(byte)
            }
            struct Failure: Decodable { let error: String }
            let code = (try? JSONDecoder().decode(Failure.self, from: data))?.error
            throw code.flatMap(OpinionLinkError.init(rawValue:)) ?? .unavailable
        }
        if path.hasPrefix("functions/v1/bsmart-withdrawals"), http.statusCode != expectedStatus {
            guard http.mimeType == "application/json" else { throw AcrossWithdrawalError.unavailable }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 4096 else { throw AcrossWithdrawalError.unavailable }
                data.append(byte)
            }
            struct Failure: Decodable { let error: String }
            let code = (try? JSONDecoder().decode(Failure.self, from: data))?.error
            throw code.flatMap(AcrossWithdrawalError.init(rawValue:)) ?? .unavailable
        }
        if path.hasPrefix("functions/v1/bsmart-feed/state"), http.statusCode == 409 {
            throw AccountAccessError.unavailable
        }
        if path.hasPrefix("functions/v1/bsmart-feed/"),
           (path.hasSuffix("/thesis") || path.hasSuffix("/like") || path.hasSuffix("/activity")),
           http.statusCode != expectedStatus {
            guard http.mimeType == "application/json" else { throw TradeThesisError.unavailable }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 4096 else { throw TradeThesisError.unavailable }
                data.append(byte)
            }
            struct Failure: Decodable { let error: String }
            let code = (try? JSONDecoder().decode(Failure.self, from: data))?.error
            throw code.flatMap(TradeThesisError.init(rawValue:)) ?? .unavailable
        }
        if path == "auth/v1/token", http.statusCode == 400 {
            var data = Data()
            for try await byte in bytes {
                guard data.count < 4096 else { throw AccountAccessError.invalidResponse }
                data.append(byte)
            }
            struct Failure: Decodable { let error_code: String? }
            let code = try? JSONDecoder().decode(Failure.self, from: data).error_code
            if ["refresh_token_not_found", "refresh_token_already_used", "session_not_found", "session_expired", "user_banned"].contains(code ?? "") {
                throw AccountAccessError.expired
            }
            throw AccountAccessError.invalidResponse
        }
        if path == "functions/v1/bsmart-profile", [409, 422].contains(http.statusCode) {
            guard http.mimeType == "application/json" else { throw AccountAccessError.invalidResponse }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 4096 else { throw AccountAccessError.invalidResponse }
                data.append(byte)
            }
            struct Failure: Decodable { let error: String }
            let result = try JSONDecoder().decode(Failure.self, from: data)
            throw AccountProfileError(rawValue: result.error) ?? .invalid
        }
        if http.statusCode == 409 { throw DeviceWalletError.recoveryRequired }
        if path.hasPrefix("functions/v1/bsmart-wallet"), [404, 503].contains(http.statusCode) { throw AccountAccessError.walletSetupRequired }
        if [404, 429].contains(http.statusCode) || http.statusCode >= 500 { throw AccountAccessError.unavailable }
        guard http.statusCode == expectedStatus,
              expectedStatus == 204 || http.mimeType == "application/json" else { throw AccountAccessError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumBytes else { throw AccountAccessError.invalidResponse }
            data.append(byte)
        }
        return data
    }
}

private final class SupabaseNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
