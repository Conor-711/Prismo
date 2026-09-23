import XCTest
@testable import BSmart

final class HyperliquidExecutionReaderTests: XCTestCase {
    private let owner = HyperliquidTradingFixture.wallet.address

    func testAllowlistedQueriesStripInheritedCredentialsAndKeepExactScope() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ExecutionURLProtocol.self]
        config.httpAdditionalHeaders = ["Authorization": "private", "Cookie": "private", "X-API-Key": "private"]
        let reader = HyperliquidExecutionReader(configuration: config, useWebSocket: false)
        let queries: [(HyperliquidExecutionQuery, [String: String])] = [
            (.dexs, ["type": "perpDexs"]), (.metadata(dex: "xyz"), ["type": "meta", "dex": "xyz"]),
            (.mode(owner: owner), ["type": "userAbstraction", "user": owner]),
            (.active(owner: owner, coin: "xyz:NVDA"), ["type": "activeAssetData", "user": owner, "coin": "xyz:NVDA"]),
            (.positions(owner: owner, dex: "xyz"), ["type": "clearinghouseState", "user": owner, "dex": "xyz"]),
            (.positions(owner: owner, dex: ""), ["type": "clearinghouseState", "user": owner, "dex": ""]),
            (.fees(owner: owner), ["type": "userFees", "user": owner]),
            (.book(coin: "xyz:NVDA"), ["type": "l2Book", "coin": "xyz:NVDA"]),
            (.builderApproval(owner: owner, builder: owner), ["type": "maxBuilderFee", "user": owner, "builder": owner])
        ]
        for (query, expected) in queries {
            let bytes = Data("{}".utf8)
            ExecutionURLProtocol.configure(data: bytes)
            let result = try await reader.read(query)
            XCTAssertEqual(result, bytes)
            let (request, body) = try XCTUnwrap(ExecutionURLProtocol.captured)
            XCTAssertEqual(request.url?.absoluteString, "https://api.hyperliquid.xyz/info")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            for key in ["Authorization", "Cookie", "X-API-Key"] { XCTAssertNil(request.value(forHTTPHeaderField: key)) }
            XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], expected)
        }
        XCTAssertNotNil(config.httpAdditionalHeaders?["Authorization"])
    }

    func testInvalidInputsFailBeforeNetwork() async throws {
        let reader = makeReader()
        for query: HyperliquidExecutionQuery in [
            .mode(owner: "0x0"), .mode(owner: "0x" + String(repeating: "0", count: 40)),
            .active(owner: owner, coin: "xyz:NVDA:BAD"), .active(owner: owner, coin: "xyz:"),
            .active(owner: owner, coin: " NVDA"), .active(owner: owner, coin: "股票"),
            .metadata(dex: "xyz:bad"), .metadata(dex: String(repeating: "a", count: 65)),
            .builderApproval(owner: owner, builder: "0x0"), .fees(owner: "0x0"), .book(coin: "xyz:")
        ] {
            ExecutionURLProtocol.configure(data: Data())
            do { _ = try await reader.read(query); XCTFail("Accepted invalid input") } catch {}
            XCTAssertNil(ExecutionURLProtocol.captured)
        }
    }

    func testStatusMIMEOriginAndResponseBounds() async throws {
        let reader = makeReader()
        for (status, mime, data, url, length) in [
            (302, "application/json", Data(), nil, nil), (429, "application/json", Data(), nil, nil),
            (503, "application/json", Data(), nil, nil), (200, "text/html", Data(), nil, nil),
            (200, "application/json", Data(), "https://example.invalid/info", nil),
            (200, "application/json", Data(), nil, "1048577"),
            (200, "application/json", Data(repeating: 32, count: 1_048_577), nil, nil)
        ] {
            ExecutionURLProtocol.configure(status: status, mime: mime, data: data, url: url, length: length)
            do { _ = try await reader.read(.dexs); XCTFail("Accepted invalid response") }
            catch { XCTAssertTrue(error is HyperliquidTradingCheckError) }
        }
        // Decoding belongs to the typed schema, not this byte transport.
        ExecutionURLProtocol.configure(data: Data("null".utf8))
        let result = try await reader.read(.dexs)
        XCTAssertEqual(result, Data("null".utf8))
    }

    func testCancellationStopsTheTransport() async throws {
        let started = expectation(description: "started"), stopped = expectation(description: "stopped")
        ExecutionURLProtocol.configure(data: Data(), hanging: (started, stopped))
        let reader = makeReader()
        let task = Task { try await reader.read(.dexs) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled request returned data") }
        catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [stopped], timeout: 2)
    }

    func testUnavailableSocketFallsBackToBoundedHTTP() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ExecutionURLProtocol.self]
        let connection = HyperliquidInfoConnection(makeSocket: { UnavailableInfoSocket() })
        let reader = HyperliquidExecutionReader(configuration: config, connection: connection)
        ExecutionURLProtocol.configure(data: Data("[]".utf8))
        let data = try await reader.read(.dexs)
        XCTAssertEqual(data, Data("[]".utf8))
        XCTAssertEqual(ExecutionURLProtocol.captured?.0.url?.absoluteString, "https://api.hyperliquid.xyz/info")
        ExecutionURLProtocol.configure(status: 429, data: Data())
        do { _ = try await reader.read(.dexs); XCTFail("Fallback accepted rate limit") }
        catch { XCTAssertTrue(error is HyperliquidTradingCheckError) }
    }

    func testMalformedSocketFallsBackOnlyToBoundedHTTPRead() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ExecutionURLProtocol.self]
        let connection = HyperliquidInfoConnection(makeSocket: { UnavailableInfoSocket(malformed: true) })
        let reader = HyperliquidExecutionReader(configuration: config, connection: connection)
        ExecutionURLProtocol.configure(data: Data("[]".utf8))
        let data = try await reader.read(.dexs)
        XCTAssertEqual(data, Data("[]".utf8))
        XCTAssertEqual(ExecutionURLProtocol.captured?.0.url?.absoluteString, "https://api.hyperliquid.xyz/info")
        ExecutionURLProtocol.configure(status: 429, data: Data())
        do { _ = try await reader.read(.dexs); XCTFail("Fallback accepted rate limit") }
        catch { XCTAssertTrue(error is HyperliquidTradingCheckError) }
    }

    private func makeReader() -> HyperliquidExecutionReader {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ExecutionURLProtocol.self]
        return .init(configuration: config, useWebSocket: false)
    }
}

private struct UnavailableInfoSocket: HyperliquidInfoSocket {
    var malformed = false
    func send(_ data: Data) async throws {}
    func receive() async throws -> Data {
        if malformed { return Data("invalid JSON".utf8) }
        throw URLError(.networkConnectionLost)
    }
    func close() {}
}

private final class ExecutionURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var response = Response()
    private static var copy: (URLRequest, Data)?
    private var stopped: XCTestExpectation?
    struct Response {
        var status = 200, mime = "application/json", data = Data()
        var url: String?, length: String?
        var hanging: (XCTestExpectation, XCTestExpectation)?
    }
    static var captured: (URLRequest, Data)? { lock.withLock { copy } }
    static func configure(status: Int = 200, mime: String = "application/json", data: Data,
                          url: String? = nil, length: String? = nil, hanging: (XCTestExpectation, XCTestExpectation)? = nil) {
        lock.withLock { response = .init(status: status, mime: mime, data: data, url: url, length: length, hanging: hanging); copy = nil }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let value = Self.lock.withLock { Self.copy = (request, body); return Self.response }
        if let hanging = value.hanging { stopped = hanging.1; hanging.0.fulfill(); return }
        var headers = ["Content-Type": value.mime]
        if let length = value.length { headers["Content-Length"] = length }
        let http = HTTPURLResponse(url: value.url.flatMap(URL.init(string:)) ?? request.url!, statusCode: value.status,
                                   httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: value.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { stopped?.fulfill() }
}
