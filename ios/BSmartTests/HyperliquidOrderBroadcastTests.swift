import XCTest
@testable import BSmart

final class HyperliquidOrderBroadcastTests: XCTestCase {
    func testExactJournalEnvelopeOnlySentOnceWithoutInheritedCredentials() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (_, quote, _, permit) = try await context.permit()
        OrderWriteURLProtocol.configure()
        let client = broadcaster()
        let response = try await client.submit(permit, lease: context.lease())
        XCTAssertEqual(response, Data("{}".utf8))
        let request = try XCTUnwrap(OrderWriteURLProtocol.request)
        XCTAssertEqual(request.url, HyperliquidOrderBroadcaster.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(OrderWriteURLProtocol.body,
                       try HyperliquidOrderCodec.envelope(quote.order, signature: context.signature(quote.order)))
        await expectJournalFailure { try await client.submit(permit, lease: context.lease()) }
        XCTAssertEqual(OrderWriteURLProtocol.count, 1)
    }

    func testStatusOriginMIMETimeoutAndSizeFailuresNeverRetry() async throws {
        for mode in OrderWriteURLProtocol.Mode.allCases where mode != .success {
            let context = OrderLifecycleContext(); defer { context.cleanup() }
            let (_, _, _, permit) = try await context.permit()
            OrderWriteURLProtocol.configure(mode)
            let response = try await broadcaster().submit(permit, lease: context.lease())
            XCTAssertNil(response, "\(mode)")
            await expectJournalFailure { try await self.broadcaster().submit(permit, lease: context.lease()) }
            XCTAssertEqual(OrderWriteURLProtocol.count, 1)
        }
    }

    func testConcurrentSubmitStartsExactlyOneRequest() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (_, _, _, permit) = try await context.permit()
        OrderWriteURLProtocol.configure()
        let client = broadcaster(), lease = context.lease()
        let count = await withTaskGroup(of: Int.self) { tasks in
            for _ in 0..<8 { tasks.addTask { (try? await client.submit(permit, lease: lease)) != nil ? 1 : 0 } }
            var total = 0
            for await value in tasks { total += value }
            return total
        }
        XCTAssertEqual(count, 1)
        XCTAssertEqual(OrderWriteURLProtocol.count, 1)
    }

    func testCancelledBeforeStartSendsNothing() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (_, _, _, permit) = try await context.permit()
        OrderWriteURLProtocol.configure()
        let client = broadcaster()
        let rejected = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try await client.submit(permit, lease: context.lease()); return false }
            catch { return true }
        }.value
        XCTAssertTrue(rejected)
        XCTAssertEqual(OrderWriteURLProtocol.count, 0)
    }

    private func broadcaster() -> HyperliquidOrderBroadcaster {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OrderWriteURLProtocol.self]
        config.httpAdditionalHeaders = ["Authorization": "private", "Cookie": "private"]
        return .init(configuration: config)
    }
}

private final class OrderWriteURLProtocol: URLProtocol, @unchecked Sendable {
    enum Mode: CaseIterable { case success, timeout, redirect, wrongOrigin, html, oversized, rateLimit }
    private static let lock = NSLock()
    private static var mode: Mode = .success
    private static var seen = 0
    private static var captured: URLRequest?
    private static var bytes: Data?
    static var request: URLRequest? { lock.withLock { captured } }
    static var body: Data? { lock.withLock { bytes } }
    static var count: Int { lock.withLock { seen } }
    static func configure(_ mode: Mode = .success) { lock.withLock { self.mode = mode; seen = 0; captured = nil; bytes = nil } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let mode = Self.lock.withLock { Self.seen += 1; Self.captured = request; Self.bytes = body; return Self.mode }
        if mode == .timeout { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return }
        let url = mode == .wrongOrigin ? URL(string: "https://example.invalid/exchange")! : request.url!
        let status = mode == .redirect ? 302 : mode == .rateLimit ? 429 : 200
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": mode == .html ? "text/html" : "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: mode == .oversized ? Data(repeating: 32, count: 8193) : Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
