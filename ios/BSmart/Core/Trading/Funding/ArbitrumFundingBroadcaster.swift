import Foundation

enum FundingSubmissionOutcome: Equatable, Sendable {
    case nodeAcknowledged(String)
    case uncertain

    var reportedHash: String? {
        if case .nodeAcknowledged(let hash) = self { return hash }
        return nil
    }
}

protocol ArbitrumFundingBroadcasting: Sendable {
    func submit(_ permit: FundingSubmissionPermit, lease: FundingSigningLease) async throws -> FundingSubmissionOutcome
}

// The only write-RPC boundary. No generic method, raw transaction or URL accepted from a Feature.
struct ArbitrumFundingBroadcaster: ArbitrumFundingBroadcasting {
    private let configuration: URLSessionConfiguration

    init(configuration: URLSessionConfiguration = .ephemeral) {
        let config = configuration.copy() as! URLSessionConfiguration
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false
        config.httpAdditionalHeaders = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        self.configuration = config
    }

    func submit(_ permit: FundingSubmissionPermit, lease: FundingSigningLease) async throws -> FundingSubmissionOutcome {
        // Do not cancel a started request with the UI task: retain its bounded response for the journal.
        try await withCheckedThrowingContinuation { continuation in
            let requestID = UUID().uuidString.lowercased()
            let delegate = FundingSubmissionResponse(id: requestID, hash: permit.hash) {
                continuation.resume(returning: $0)
            }
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            do {
                try permit.start(lease: lease) { raw in
                    struct Payload: Encodable {
                        let jsonrpc = "2.0"
                        let method = "eth_sendRawTransaction"
                        let id: String
                        let params: [String]
                    }
                    var request = URLRequest(url: ArbitrumFundingRPC.endpoint)
                    request.httpMethod = "POST"
                    request.httpBody = try JSONEncoder().encode(Payload(id: requestID, params: [FundingHex.encode(raw)]))
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

    static func outcome(_ data: Data, id: String, hash: String) -> FundingSubmissionOutcome {
        guard data.count <= FundingSubmissionResponse.limit,
              let value = try? JSONDecoder().decode(FundingRPCValue.self, from: data),
              case .object(let fields) = value, Set(fields.keys) == ["jsonrpc", "id", "result"],
              fields["jsonrpc"] == .string("2.0"), fields["id"] == .string(id), fields["result"] == .string(hash),
              FundingHex.decode(hash)?.count == 32 else { return .uncertain }
        return .nodeAcknowledged(hash)
    }
}

// URLSession serializes delegate callbacks. Bound memory before accepting response bytes.
private final class FundingSubmissionResponse: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let limit = 16_384
    private let id: String
    private let expectedHash: String
    private let completion: @Sendable (FundingSubmissionOutcome) -> Void
    private var data = Data()
    private var finished = false
    private var acceptedResponse = false

    init(id: String, hash: String, completion: @escaping @Sendable (FundingSubmissionOutcome) -> Void) {
        self.id = id
        expectedHash = hash
        self.completion = completion
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard !finished, let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url == ArbitrumFundingRPC.endpoint, response.mimeType == "application/json",
              response.expectedContentLength <= Self.limit else {
            completionHandler(.cancel)
            finish(.uncertain, session: session)
            return
        }
        acceptedResponse = true
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive bytes: Data) {
        guard !finished else { return }
        guard bytes.count <= Self.limit - data.count else {
            dataTask.cancel()
            finish(.uncertain, session: session)
            return
        }
        data.append(bytes)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result: FundingSubmissionOutcome = error == nil && acceptedResponse
            ? ArbitrumFundingBroadcaster.outcome(data, id: id, hash: expectedHash) : .uncertain
        finish(result, session: session)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
        finish(.uncertain, session: session)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                          ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }

    private func finish(_ result: FundingSubmissionOutcome, session: URLSession) {
        guard !finished else { return }
        finished = true
        data.removeAll()
        session.invalidateAndCancel()
        completion(result)
    }
}
