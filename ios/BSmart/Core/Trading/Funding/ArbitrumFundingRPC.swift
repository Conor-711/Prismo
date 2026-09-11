import Foundation

indirect enum FundingRPCValue: Codable, Equatable, Sendable {
    case string(String), integer(Int), bool(Bool), array([Self]), object([String: Self]), null

    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else if let value = try? box.decode(Int.self) { self = .integer(value) }
        else if let value = try? box.decode([Self].self) { self = .array(value) }
        else { self = .object(try box.decode([String: Self].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .string(let value): try box.encode(value)
        case .integer(let value): try box.encode(value)
        case .bool(let value): try box.encode(value)
        case .array(let value): try box.encode(value)
        case .object(let value): try box.encode(value)
        case .null: try box.encodeNil()
        }
    }

    func text() throws -> String {
        guard case .string(let value) = self else { throw FundingPreflightError.invalidResponse }
        return value
    }
}

struct FundingRPCRequest: Encodable, Sendable {
    enum Method: String, Encodable, Sendable {
        case chainID = "eth_chainId", block = "eth_getBlockByNumber", balance = "eth_getBalance"
        case code = "eth_getCode", call = "eth_call", nonce = "eth_getTransactionCount"
        case gasPrice = "eth_gasPrice", estimate = "eth_estimateGas"
        case transaction = "eth_getTransactionByHash", receipt = "eth_getTransactionReceipt"
    }
    let jsonrpc = "2.0"
    let id: String
    let method: Method
    let params: [FundingRPCValue]

    init(_ method: Method, _ params: [FundingRPCValue] = []) {
        id = UUID().uuidString.lowercased()
        self.method = method
        self.params = params
    }
}

protocol FundingRPCProviding: Sendable {
    // Results are returned in request order, regardless of server batch ordering.
    func read(_ requests: [FundingRPCRequest]) async throws -> [FundingRPCValue]
}

typealias ArbitrumFundingRPCProviding = FundingRPCProviding

final class ArbitrumFundingRPC: ArbitrumFundingRPCProviding, @unchecked Sendable {
    static let endpoint = URL(string: "https://arb1.arbitrum.io/rpc")!
    private let transport: FundingReadRPC

    init(configuration: URLSessionConfiguration = .ephemeral) {
        transport = FundingReadRPC(network: .arbitrum, configuration: configuration)
    }
    func read(_ requests: [FundingRPCRequest]) async throws -> [FundingRPCValue] { try await transport.read(requests) }
    static func results(_ data: Data, requests: [FundingRPCRequest]) throws -> [FundingRPCValue] {
        try FundingReadRPC.results(data, requests: requests)
    }
}

final class HyperEVMFundingRPC: FundingRPCProviding, @unchecked Sendable {
    static let endpoint = URL(string: "https://rpc.hyperliquid.xyz/evm")!
    private let transport: FundingReadRPC

    init(configuration: URLSessionConfiguration = .ephemeral) {
        transport = FundingReadRPC(network: .hyperEVM, configuration: configuration)
    }
    func read(_ requests: [FundingRPCRequest]) async throws -> [FundingRPCValue] { try await transport.read(requests) }
}

private final class FundingReadRPC: @unchecked Sendable {
    enum Network { case arbitrum, hyperEVM }
    private let endpoint: URL
    private let session: URLSession
    private static let responseLimit = 262_144

    init(network: Network, configuration: URLSessionConfiguration) {
        endpoint = network == .arbitrum ? ArbitrumFundingRPC.endpoint : HyperEVMFundingRPC.endpoint
        let config = configuration.copy() as! URLSessionConfiguration
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpAdditionalHeaders = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config, delegate: FundingRPCNoRedirects(), delegateQueue: nil)
    }

    func read(_ requests: [FundingRPCRequest]) async throws -> [FundingRPCValue] {
        guard (1...32).contains(requests.count), Set(requests.map(\.id)).count == requests.count else {
            throw FundingPreflightError.invalidResponse
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(requests)
        guard request.httpBody!.count <= 32_768 else { throw FundingPreflightError.invalidResponse }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  response.url == endpoint, response.mimeType == "application/json",
                  response.expectedContentLength <= Self.responseLimit else { throw FundingPreflightError.invalidResponse }
            var data = Data()
            for try await byte in bytes {
                guard data.count < Self.responseLimit else { throw FundingPreflightError.invalidResponse }
                data.append(byte)
            }
            try Task.checkCancellation()
            return try Self.results(data, requests: requests)
        } catch is CancellationError { throw CancellationError() }
        catch let error as FundingPreflightError { throw error }
        catch { throw FundingPreflightError.unavailable }
    }

    static func results(_ data: Data, requests: [FundingRPCRequest]) throws -> [FundingRPCValue] {
        struct Response: Decodable {
            let jsonrpc: String
            let id: String
            let result: FundingRPCValue?
            let error: FundingRPCValue?

            private enum CodingKeys: String, CodingKey { case jsonrpc, id, result, error }

            init(from decoder: Decoder) throws {
                let box = try decoder.container(keyedBy: CodingKeys.self)
                guard box.contains(.result) != box.contains(.error) else { throw FundingPreflightError.invalidResponse }
                jsonrpc = try box.decode(String.self, forKey: .jsonrpc)
                id = try box.decode(String.self, forKey: .id)
                result = box.contains(.result) ? try box.decode(FundingRPCValue.self, forKey: .result) : nil
                error = box.contains(.error) ? try box.decode(FundingRPCValue.self, forKey: .error) : nil
            }
        }
        let rows: [Response]
        do { rows = try JSONDecoder().decode([Response].self, from: data) }
        catch { throw FundingPreflightError.invalidResponse }
        guard rows.count == requests.count, Set(rows.map(\.id)) == Set(requests.map(\.id)),
              Set(rows.map(\.id)).count == rows.count else { throw FundingPreflightError.invalidResponse }
        let map = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        return try requests.map { request in
            guard let row = map[request.id], row.jsonrpc == "2.0" else { throw FundingPreflightError.invalidResponse }
            if row.error != nil {
                guard row.result == nil else { throw FundingPreflightError.invalidResponse }
                if request.method == .estimate || request.method == .call { throw FundingPreflightError.simulationFailed }
                throw FundingPreflightError.unavailable
            }
            guard let result = row.result,
                  result != .null || [.transaction, .receipt].contains(request.method) else { throw FundingPreflightError.invalidResponse }
            return result
        }
    }
}

private final class FundingRPCNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
