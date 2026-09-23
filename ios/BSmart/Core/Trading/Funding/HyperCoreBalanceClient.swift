import Foundation

enum HyperCoreBalanceQuery: String, Encodable, Sendable {
    case mode = "userAbstraction", spot = "spotClearinghouseState", perps = "clearinghouseState"
    case portfolio
}

protocol HyperCoreBalanceReading: Sendable {
    func read(_ query: HyperCoreBalanceQuery, owner: String) async throws -> FundingRPCValue
}

final class HyperCoreBalanceClient: HyperCoreBalanceReading, @unchecked Sendable {
    static let endpoint = URL(string: "https://api.hyperliquid.xyz/info")!
    private let session: URLSession
    private static let responseLimit = 262_144

    init(configuration: URLSessionConfiguration = .ephemeral) {
        let config = configuration.copy() as! URLSessionConfiguration
        config.urlCache = nil; config.urlCredentialStorage = nil; config.httpCookieStorage = nil
        config.httpShouldSetCookies = false; config.httpAdditionalHeaders = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 8; config.timeoutIntervalForResource = 12
        session = URLSession(configuration: config, delegate: HyperCoreBalanceNoRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func read(_ query: HyperCoreBalanceQuery, owner: String) async throws -> FundingRPCValue {
        guard TradingWalletChallenge.validAddress(owner) else { throw HyperCoreBalanceError.invalidResponse }
        try Task.checkCancellation()
        for attempt in 0..<2 {
            do { return try await readOnce(query, owner: owner) }
            catch is RetryableReadError {
                guard attempt == 0 else { throw HyperCoreBalanceError.unavailable }
                try await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        throw HyperCoreBalanceError.unavailable
    }

    private func readOnce(_ query: HyperCoreBalanceQuery, owner: String) async throws -> FundingRPCValue {
        struct Body: Encodable { let type: HyperCoreBalanceQuery; let user: String; let dex: String? }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(Body(type: query, user: owner, dex: query == .perps ? "" : nil))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let responseLimit = query == .portfolio ? 1_048_576 : Self.responseLimit
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else { throw HyperCoreBalanceError.unavailable }
            if [429, 500, 502, 503, 504].contains(http.statusCode) { throw RetryableReadError() }
            guard http.statusCode == 200,
                  http.url == Self.endpoint, http.mimeType == "application/json",
                  http.expectedContentLength <= responseLimit else { throw HyperCoreBalanceError.unavailable }
            var data = Data()
            for try await byte in bytes {
                guard data.count < responseLimit else { throw HyperCoreBalanceError.invalidResponse }
                data.append(byte)
            }
            try Task.checkCancellation()
            return try JSONDecoder().decode(FundingRPCValue.self, from: data)
        } catch is CancellationError { throw CancellationError() }
        catch let error as RetryableReadError { throw error }
        catch let error as HyperCoreBalanceError { throw error }
        catch let error as URLError where [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code) {
            if Task.isCancelled { throw CancellationError() }
            throw RetryableReadError()
        }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw HyperCoreBalanceError.unavailable
        }
    }
}

private struct RetryableReadError: Error {}

private final class HyperCoreBalanceNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
