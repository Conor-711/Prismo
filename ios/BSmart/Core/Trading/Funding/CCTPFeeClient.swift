import Foundation

protocol CCTPFeeProviding: Sendable {
    func schedule() async throws -> CCTPFeeSchedule
}

final class CCTPFeeClient: CCTPFeeProviding, @unchecked Sendable {
    static let endpoint = URL(string: "https://iris-api.circle.com/v2/burn/USDC/fees/3/19?forward=true&hyperCoreDeposit=true")!
    private let session: URLSession

    init(configuration config: URLSessionConfiguration = .ephemeral) {
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpAdditionalHeaders = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config, delegate: CCTPNoRedirects(), delegateQueue: nil)
    }

    func schedule() async throws -> CCTPFeeSchedule {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  response.url == Self.endpoint, response.expectedContentLength <= 16_384,
                  response.mimeType == "application/json" else { throw CCTPFundingError.invalidResponse }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 16_384 else { throw CCTPFundingError.invalidResponse }
                data.append(byte)
            }
            try Task.checkCancellation()
            return try CCTPFeeSchedule.decode(data, receivedAt: Date())
        } catch is CancellationError { throw CancellationError() }
        catch let error as CCTPFundingError { throw error }
        catch { throw CCTPFundingError.unavailable }
    }
}

private final class CCTPNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
