import Foundation

protocol HyperliquidOrderBroadcasting: Sendable {
    func submit(_ permit: HyperliquidOrderSubmissionPermit, lease: FundingSigningLease) async throws -> Data?
}

protocol UnifiedAccountSetupBroadcasting: Sendable {
    func submit(_ permit: UnifiedAccountSetupPermit, signature: String, lease: FundingSigningLease) async throws -> Data?
}

protocol HyperliquidLeverageBroadcasting: Sendable {
    func submit(_ permit: HyperliquidLeveragePermit, signature: String, lease: FundingSigningLease) async throws -> Data?
}

// Only a journal-issued, one-use permit can start an exchange write. No raw action/URL API.
struct HyperliquidOrderBroadcaster: HyperliquidOrderBroadcasting, UnifiedAccountSetupBroadcasting, HyperliquidLeverageBroadcasting {
    static let endpoint = URL(string: "https://api.hyperliquid.xyz/exchange")!
    private let configuration: URLSessionConfiguration

    init(configuration: URLSessionConfiguration = .ephemeral) {
        let config = configuration.copy() as! URLSessionConfiguration
        config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false; config.httpAdditionalHeaders = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        self.configuration = config
    }

    func submit(_ permit: HyperliquidOrderSubmissionPermit, lease: FundingSigningLease) async throws -> Data? {
        try await send { operation in try permit.start(lease: lease, operation) }
    }

    private func send(start: (@escaping (Data) -> Void) throws -> Void) async throws -> Data? {
        // Preserve the bounded response if the presenting view disappears after submission.
        try await withCheckedThrowingContinuation { continuation in
            let delegate = HyperliquidExchangeResponse { continuation.resume(returning: $0) }
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            do {
                try start { body in
                    var request = URLRequest(url: Self.endpoint)
                    request.httpMethod = "POST"; request.httpBody = body
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
                    session.dataTask(with: request).resume()
                }
            } catch {
                session.invalidateAndCancel()
                continuation.resume(throwing: error)
            }
        }
    }

    func submit(_ permit: UnifiedAccountSetupPermit, signature: String, lease: FundingSigningLease) async throws -> Data? {
        try await send { operation in try permit.start(signature: signature, lease: lease, operation) }
    }

    func submit(_ permit: HyperliquidLeveragePermit, signature: String, lease: FundingSigningLease) async throws -> Data? {
        try await send { operation in try permit.start(signature: signature, lease: lease, operation) }
    }
}

private final class HyperliquidExchangeResponse: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private static let limit = 8192
    private let completion: @Sendable (Data?) -> Void
    private var data = Data()
    private var finished = false
    private var accepted = false

    init(completion: @escaping @Sendable (Data?) -> Void) { self.completion = completion }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard !finished, let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url == HyperliquidOrderBroadcaster.endpoint, http.mimeType == "application/json",
              http.expectedContentLength <= Self.limit else {
            completionHandler(.cancel); finish(nil, session: session); return
        }
        accepted = true; completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive bytes: Data) {
        guard !finished else { return }
        guard bytes.count <= Self.limit - data.count else { finish(nil, session: session); return }
        data.append(bytes)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error == nil && accepted ? data : nil, session: session)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil); finish(nil, session: session)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                          ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }

    private func finish(_ response: Data?, session: URLSession) {
        guard !finished else { return }
        finished = true; data.removeAll(); session.invalidateAndCancel(); completion(response)
    }
}
