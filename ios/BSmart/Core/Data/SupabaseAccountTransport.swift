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

    init(configuration: SupabaseAccountConfiguration, sessionConfiguration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration
        let config = sessionConfiguration.copy() as! URLSessionConfiguration
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.httpAdditionalHeaders = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
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
        guard let http = response as? HTTPURLResponse, http.url == request.url,
              response.expectedContentLength <= 131072 else { throw AccountAccessError.invalidResponse }
        if http.statusCode == 401 { throw AccountAccessError.expired }
        if http.statusCode == 409 { throw DeviceWalletError.recoveryRequired }
        if path.hasPrefix("functions/"), [404, 503].contains(http.statusCode) { throw AccountAccessError.walletSetupRequired }
        if [404, 429, 503].contains(http.statusCode) { throw AccountAccessError.unavailable }
        guard http.statusCode == expectedStatus,
              expectedStatus == 204 || http.mimeType == "application/json" else { throw AccountAccessError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 131072 else { throw AccountAccessError.invalidResponse }
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
