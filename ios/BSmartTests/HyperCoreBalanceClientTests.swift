import XCTest
@testable import BSmart

final class HyperCoreBalanceClientTests: XCTestCase {
    func testOnlyFixedReadQueriesAreSentWithoutCredentials() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CoreBalanceURLProtocol.self]
        config.httpAdditionalHeaders = ["Authorization": "must-not-leave-device", "Cookie": "private"]
        let client = HyperCoreBalanceClient(configuration: config)
        for query in [HyperCoreBalanceQuery.mode, .spot, .perps] {
            CoreBalanceURLProtocol.configure(data: Data(#""unifiedAccount""#.utf8))
            let value = try await client.read(query, owner: CoreBalanceFixture.wallet.address)
            XCTAssertEqual(value, .string("unifiedAccount"))
            let captured = try XCTUnwrap(CoreBalanceURLProtocol.captured)
            XCTAssertEqual(captured.0.url?.absoluteString, "https://api.hyperliquid.xyz/info")
            XCTAssertEqual(captured.0.httpMethod, "POST")
            XCTAssertNil(captured.0.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(captured.0.value(forHTTPHeaderField: "Cookie"))
            XCTAssertEqual(captured.0.value(forHTTPHeaderField: "Cache-Control"), "no-store")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: captured.1) as? [String: String])
            var expected = ["type": query.rawValue, "user": CoreBalanceFixture.wallet.address]
            if query == .perps { expected["dex"] = "" }
            XCTAssertEqual(body, expected)
        }
        XCTAssertNotNil(config.httpAdditionalHeaders?["Authorization"])
    }

    func testHTTPFailuresRedirectsWrongOriginAndOversizeAreErrors() async {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CoreBalanceURLProtocol.self]
        let client = HyperCoreBalanceClient(configuration: config)
        for (status, mime, bytes, url) in [
            (302, "application/json", Data(), nil), (429, "application/json", Data(), nil),
            (500, "application/json", Data(), nil), (200, "text/html", Data(), nil),
            (200, "application/json", Data("bad json".utf8), nil),
            (200, "application/json", Data(repeating: 32, count: 262_145), nil),
            (200, "application/json", Data(#""unifiedAccount""#.utf8), URL(string: "https://example.invalid/info"))
        ] {
            CoreBalanceURLProtocol.configure(status: status, mime: mime, data: bytes, url: url)
            do { _ = try await client.read(.spot, owner: CoreBalanceFixture.wallet.address); XCTFail("Accepted invalid response") }
            catch { XCTAssertTrue(error is HyperCoreBalanceError) }
        }
    }

    func testInvalidOwnerIsRejectedBeforeNetworkDisclosure() async {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CoreBalanceURLProtocol.self]
        let client = HyperCoreBalanceClient(configuration: config)
        for owner in ["0x0", "https://example.invalid", "0x" + String(repeating: "0", count: 40)] {
            CoreBalanceURLProtocol.configure(data: Data())
            do { _ = try await client.read(.mode, owner: owner); XCTFail("Accepted owner") } catch {}
            XCTAssertNil(CoreBalanceURLProtocol.captured)
        }
    }

    func testTransientRateLimitRetriesReadOnlyBalanceRequest() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CoreBalanceURLProtocol.self]
        let client = HyperCoreBalanceClient(configuration: config)
        CoreBalanceURLProtocol.configureSequence([
            (429, Data()), (200, Data(#""unifiedAccount""#.utf8))
        ])
        let value = try await client.read(.mode, owner: CoreBalanceFixture.wallet.address)
        XCTAssertEqual(value, .string("unifiedAccount"))
        XCTAssertEqual(CoreBalanceURLProtocol.requestCount, 2)
    }

    func testNonRetryableFailureDoesNotProbeAgain() async {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CoreBalanceURLProtocol.self]
        let client = HyperCoreBalanceClient(configuration: config)
        CoreBalanceURLProtocol.configureSequence([
            (403, Data()), (200, Data(#""unifiedAccount""#.utf8))
        ])
        do { _ = try await client.read(.mode, owner: CoreBalanceFixture.wallet.address); XCTFail("Accepted 403") }
        catch { XCTAssertEqual(error as? HyperCoreBalanceError, .unavailable) }
        XCTAssertEqual(CoreBalanceURLProtocol.requestCount, 1)
    }

    func testCancellationStopsAnOutstandingNetworkRequest() async {
        let started = expectation(description: "Read started"), stopped = expectation(description: "Read cancelled")
        HangingCoreBalanceURLProtocol.configure(started: started, stopped: stopped)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [HangingCoreBalanceURLProtocol.self]
        let client = HyperCoreBalanceClient(configuration: config)
        let request = Task { try await client.read(.mode, owner: CoreBalanceFixture.wallet.address) }
        await fulfillment(of: [started], timeout: 2)
        request.cancel()
        do { _ = try await request.value; XCTFail("Cancelled read returned a balance") }
        catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [stopped], timeout: 2)
    }
}

private final class HangingCoreBalanceURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var signals: (started: XCTestExpectation, stopped: XCTestExpectation)?
    private var stopped: XCTestExpectation?
    static func configure(started: XCTestExpectation, stopped: XCTestExpectation) {
        lock.withLock { signals = (started, stopped) }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let signals = Self.lock.withLock { Self.signals }
        stopped = signals?.stopped
        signals?.started.fulfill()
    }
    override func stopLoading() { stopped?.fulfill() }
}

private final class CoreBalanceURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var response = (status: 200, mime: "application/json", data: Data(), url: Optional<URL>.none)
    private static var sequence: [(status: Int, data: Data)] = []
    private static var count = 0
    private static var copy: (URLRequest, Data)?
    static var captured: (URLRequest, Data)? { lock.withLock { copy } }
    static var requestCount: Int { lock.withLock { count } }
    static func configure(status: Int = 200, mime: String = "application/json", data: Data, url: URL? = nil) {
        lock.withLock { response = (status, mime, data, url); sequence = []; count = 0; copy = nil }
    }
    static func configureSequence(_ responses: [(Int, Data)]) {
        lock.withLock {
            sequence = responses.map { (status: $0.0, data: $0.1) }
            count = 0; copy = nil
        }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let response = Self.lock.withLock { () -> (status: Int, mime: String, data: Data, url: URL?) in
            Self.copy = (request, body)
            Self.count += 1
            if !Self.sequence.isEmpty {
                let next = Self.sequence.removeFirst()
                return (next.status, "application/json", next.data, nil)
            }
            return Self.response
        }
        let http = HTTPURLResponse(url: response.url ?? request.url!, statusCode: response.status, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": response.mime])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
