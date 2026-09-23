import Foundation
import OSLog

enum HyperliquidTradingCheckError: Error, Equatable {
    case unavailable, invalidResponse, stale, accountChanged, unsupportedCollateral
    case leverageChanged, exceedsCapacity, invalidReduction
}

enum HyperliquidExecutionQuery: Equatable, Sendable {
    case dexs
    case metadata(dex: String)
    case mode(owner: String)
    case active(owner: String, coin: String)
    case positions(owner: String, dex: String)
    case openOrders(owner: String, dex: String)
    case book(coin: String)
    case fees(owner: String)
    case builderApproval(owner: String, builder: String)
    case orderStatus(owner: String, cloid: String)
    case fills(owner: String, start: UInt64, end: UInt64)

    var diagnosticKind: String {
        switch self {
        case .dexs: "dexs"
        case .metadata: "metadata"
        case .mode: "mode"
        case .active: "active"
        case .positions: "positions"
        case .openOrders: "open_orders"
        case .book: "book"
        case .fees: "fees"
        case .builderApproval: "builder_approval"
        case .orderStatus: "order_status"
        case .fills: "fills"
        }
    }

    func body() throws -> Data {
        var fields: [String: String]
        switch self {
        case let .fills(owner, start, end):
            guard TradingWalletChallenge.validAddress(owner), start <= end, end <= 9_007_199_254_740_991,
                  end - start <= 64_000 else { throw HyperliquidTradingCheckError.invalidResponse }
            return try JSONEncoder().encode(FillRequest(user: owner, startTime: start, endTime: end))
        case .dexs: fields = ["type": "perpDexs"]
        case let .metadata(dex): fields = ["type": "meta", "dex": dex]
        case let .mode(owner): fields = ["type": "userAbstraction", "user": owner]
        case let .active(owner, coin): fields = ["type": "activeAssetData", "user": owner, "coin": coin]
        case let .positions(owner, dex): fields = ["type": "clearinghouseState", "user": owner, "dex": dex]
        case let .openOrders(owner, dex): fields = ["type": "openOrders", "user": owner, "dex": dex]
        case let .book(coin): fields = ["type": "l2Book", "coin": coin]
        case let .fees(owner): fields = ["type": "userFees", "user": owner]
        case let .builderApproval(owner, builder): fields = ["type": "maxBuilderFee", "user": owner, "builder": builder]
        case let .orderStatus(owner, cloid):
            guard FundingHex.decode(cloid)?.count == 16 else { throw HyperliquidTradingCheckError.invalidResponse }
            fields = ["type": "orderStatus", "user": owner, "oid": cloid]
        }
        if let owner = fields["user"], !TradingWalletChallenge.validAddress(owner) {
            throw HyperliquidTradingCheckError.accountChanged
        }
        if let builder = fields["builder"], !TradingWalletChallenge.validAddress(builder) {
            throw HyperliquidTradingCheckError.invalidResponse
        }
        if let dex = fields["dex"], !dex.isEmpty && !Self.validComponent(dex) {
            throw HyperliquidTradingCheckError.invalidResponse
        }
        if let coin = fields["coin"] {
            let parts = coin.split(separator: ":", omittingEmptySubsequences: false)
            guard (1...2).contains(parts.count), parts.allSatisfy({ Self.validComponent(String($0)) }) else {
                throw HyperliquidTradingCheckError.invalidResponse
            }
        }
        return try JSONEncoder().encode(fields)
    }

    private struct FillRequest: Encodable {
        let type = "userFillsByTime"
        let user: String
        let startTime, endTime: UInt64
        let aggregateByTime = false
    }

    private static func validComponent(_ text: String) -> Bool {
        (1...64).contains(text.utf8.count) && text.utf8.allSatisfy { (33...126).contains($0) && $0 != 58 }
    }
}

protocol HyperliquidExecutionReading: Sendable {
    func read(_ query: HyperliquidExecutionQuery) async throws -> Data
}

final class HyperliquidExecutionReader: HyperliquidExecutionReading, @unchecked Sendable {
    static let endpoint = URL(string: "https://api.hyperliquid.xyz/info")!
    private static let logger = Logger(subsystem: "today.bsmart.ios", category: "TradingReadLatency")
    private let session: URLSession
    private let infoConnection: HyperliquidInfoConnection?

    init(configuration: URLSessionConfiguration = .ephemeral, useWebSocket: Bool = true,
         connection: HyperliquidInfoConnection = .shared) {
        infoConnection = useWebSocket ? connection : nil
        let config = configuration.copy() as! URLSessionConfiguration
        config.urlCache = nil; config.urlCredentialStorage = nil; config.httpCookieStorage = nil
        config.httpShouldSetCookies = false; config.httpAdditionalHeaders = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 8; config.timeoutIntervalForResource = 12
        session = URLSession(configuration: config, delegate: ExecutionNoRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func read(_ query: HyperliquidExecutionQuery) async throws -> Data {
        try Task.checkCancellation()
        let started = ContinuousClock.now
        var transport = infoConnection == nil ? "http" : "websocket"
        var outcome = "ok"
        defer {
            let elapsed = started.duration(to: .now).components
            let milliseconds = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
            Self.logger.notice("query=\(query.diagnosticKind, privacy: .public) transport=\(transport, privacy: .public) outcome=\(outcome, privacy: .public) elapsed_ms=\(milliseconds)")
        }
        if let infoConnection {
            do { return try await infoConnection.read(query) }
            catch is CancellationError { throw CancellationError() }
            catch HyperliquidInfoSocketError.unavailable {
                // Read-only fallback, never an exchange write or a replayed signed order.
                try Task.checkCancellation()
                transport = "http_fallback"
            }
            catch HyperliquidInfoSocketError.rejected {
                outcome = "socket_rejected"
                throw HyperliquidTradingCheckError.unavailable
            }
            catch HyperliquidInfoSocketError.invalidResponse {
                // A malformed socket frame does not authorize an order. Retry the
                // read-only observation over the bounded HTTP transport.
                transport = "http_fallback"
            }
        }
        let responseLimit: Int
        if case .fills = query { responseLimit = 2_097_152 } else { responseLimit = 1_048_576 }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.httpBody = try query.body()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else {
                outcome = "http_invalid"
                throw HyperliquidTradingCheckError.unavailable
            }
            guard http.statusCode == 200 else {
                outcome = "http_\(http.statusCode)"
                throw HyperliquidTradingCheckError.unavailable
            }
            guard http.url == Self.endpoint, http.mimeType == "application/json",
                  http.expectedContentLength <= responseLimit else {
                outcome = "http_invalid"
                throw HyperliquidTradingCheckError.unavailable
            }
            var data = Data()
            for try await byte in bytes {
                guard data.count < responseLimit else {
                    outcome = "http_oversize"
                    throw HyperliquidTradingCheckError.invalidResponse
                }
                data.append(byte)
            }
            try Task.checkCancellation()
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as HyperliquidTradingCheckError { throw error }
        catch {
            if Task.isCancelled { throw CancellationError() }
            outcome = "http_transport"
            throw HyperliquidTradingCheckError.unavailable
        }
    }
}

private final class ExecutionNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
