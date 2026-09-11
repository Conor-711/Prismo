import XCTest
@testable import BSmart

final class ArbitrumFundingRPCTests: XCTestCase {
    func testNullMeansNotFoundOnlyForHashLookups() throws {
        for method in [FundingRPCRequest.Method.transaction, .receipt, .block, .nonce, .balance, .call] {
            let request = FundingRPCRequest(method)
            let data = try JSONSerialization.data(withJSONObject: [["jsonrpc": "2.0", "id": request.id, "result": NSNull()]])
            if method == .transaction || method == .receipt {
                XCTAssertEqual(try ArbitrumFundingRPC.results(data, requests: [request]), [.null])
            } else { XCTAssertThrowsError(try ArbitrumFundingRPC.results(data, requests: [request])) }
        }
    }

    func testStrictBatchCorrelationAndAmbiguousResultsRejected() throws {
        let requests = [FundingRPCRequest(.chainID), FundingRPCRequest(.gasPrice)]
        func response(_ id: String, _ result: String) -> [String: Any] {
            ["jsonrpc": "2.0", "id": id, "result": result]
        }
        let first = response(requests[0].id, "0xa4b1")
        let second = response(requests[1].id, "0x1")
        let correct = try JSONSerialization.data(withJSONObject: [second, first])
        XCTAssertEqual(try ArbitrumFundingRPC.results(correct, requests: requests), [.string("0xa4b1"), .string("0x1")])
        for malformed in [
            [], [first], [first, first], [first, second, second], [first, response("unknown", "0x1")],
            [first, ["jsonrpc": "1.0", "id": requests[1].id, "result": "0x1"]],
            [first, ["jsonrpc": "2.0", "id": requests[1].id, "result": NSNull()]],
            [first, ["jsonrpc": "2.0", "id": requests[1].id, "result": "0x1", "error": ["code": -32000]]],
            [first, ["jsonrpc": "2.0", "id": requests[1].id, "result": "0x1", "error": NSNull()]],
            [first, ["jsonrpc": "2.0", "id": 1, "result": "0x1"]]
        ] as [[[String: Any]]] {
            let data = try JSONSerialization.data(withJSONObject: malformed)
            XCTAssertThrowsError(try ArbitrumFundingRPC.results(data, requests: requests))
        }
    }

    func testRPCRevertsCannotBecomeSimulationSuccess() throws {
        let requests = [FundingRPCRequest(.estimate)]
        let data = try JSONSerialization.data(withJSONObject: [["jsonrpc": "2.0", "id": requests[0].id,
            "error": ["code": 3, "message": "execution reverted", "data": "0x"]]])
        XCTAssertThrowsError(try ArbitrumFundingRPC.results(data, requests: requests)) {
            XCTAssertEqual($0 as? FundingPreflightError, .simulationFailed)
        }
    }

    func testTransportPinsEndpointAndStripsCredentials() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FundingURLProtocol.self]
        config.httpAdditionalHeaders = ["Authorization": "must-not-leave", "Cookie": "must-not-leave"]
        FundingURLProtocol.configure(status: 200, mime: "application/json", oversized: false)
        let client = ArbitrumFundingRPC(configuration: config)
        let result = try await client.read([.init(.chainID)])
        XCTAssertEqual(result, [.string("0xa4b1")])
        let request = try XCTUnwrap(FundingURLProtocol.captured)
        XCTAssertEqual(request.url?.absoluteString, "https://arb1.arbitrum.io/rpc")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
    }

    func testHTTPRedirectHTMLRateLimitAndResponseSizeFailClosed() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FundingURLProtocol.self]
        let client = ArbitrumFundingRPC(configuration: config)
        for (status, mime, oversized) in [(302, "application/json", false), (429, "application/json", false),
            (500, "application/json", false), (200, "text/html", false), (200, "application/json", true)] {
            FundingURLProtocol.configure(status: status, mime: mime, oversized: oversized)
            do { _ = try await client.read([.init(.chainID)]); XCTFail("Accepted \(status)") }
            catch { XCTAssertTrue(error is FundingPreflightError) }
        }
    }
}

private final class FundingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var configuration = (status: 200, mime: "application/json", oversized: false)
    private static var requestCopy: URLRequest?
    static var captured: URLRequest? { lock.withLock { requestCopy } }
    static func configure(status: Int, mime: String, oversized: Bool) {
        lock.withLock { configuration = (status, mime, oversized); requestCopy = nil }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let config = Self.lock.withLock { Self.requestCopy = request; return Self.configuration }
        do {
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    guard count > 0 else { break }
                    body.append(contentsOf: bytes.prefix(count))
                }
            }
            guard let requests = try JSONSerialization.jsonObject(with: body) as? [[String: Any]] else {
                throw FundingPreflightError.invalidResponse
            }
            let data = config.oversized ? Data(repeating: 32, count: 262_145) : try JSONSerialization.data(withJSONObject:
                requests.reversed().map { ["jsonrpc": "2.0", "id": $0["id"]!, "result": "0xa4b1"] })
            let response = HTTPURLResponse(url: request.url!, statusCode: config.status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": config.mime])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
