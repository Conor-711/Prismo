import XCTest
@testable import BSmart

final class CCTPFeeClientTests: XCTestCase {
    func testRequestUsesOnlyFixedPublicMainnetRoute() async throws {
        let client = makeClient()
        FeeURLProtocol.setResponse(status: 200, type: "application/json", data: Data(CCTPDepositQuoteTests.response.utf8))
        let result = try await client.schedule()
        XCTAssertEqual(result.forwardingFeeUnits, 200_000)
        let request = try XCTUnwrap(FeeURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString,
            "https://iris-api.circle.com/v2/burn/USDC/fees/3/19?forward=true&hyperCoreDeposit=true")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
    }

    func testHTTPFailuresRedirectsAndUnexpectedContentCannotBecomeFees() async {
        let client = makeClient()
        for (status, type, data) in [
            (302, "application/json", Data(CCTPDepositQuoteTests.response.utf8)),
            (429, "application/json", Data(CCTPDepositQuoteTests.response.utf8)),
            (500, "application/json", Data(CCTPDepositQuoteTests.response.utf8)),
            (200, "text/html", Data(CCTPDepositQuoteTests.response.utf8)),
            (200, "application/json", Data("{}".utf8)),
            (200, "application/json", Data(repeating: 32, count: 16_385))
        ] {
            FeeURLProtocol.setResponse(status: status, type: type, data: data)
            do { _ = try await client.schedule(); XCTFail("Accepted status \(status) / \(type)") }
            catch { XCTAssertTrue(error is CCTPFundingError) }
        }
    }

    private func makeClient() -> CCTPFeeClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FeeURLProtocol.self]
        return CCTPFeeClient(configuration: config)
    }
}

private final class FeeURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var payload: (Int, String, Data) = (500, "application/json", Data())
    private static var captured: URLRequest?

    static var lastRequest: URLRequest? { lock.withLock { captured } }

    static func setResponse(status: Int, type: String, data: Data) {
        lock.withLock { payload = (status, type, data); captured = nil }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, type, data) = Self.lock.withLock { Self.captured = request; return Self.payload }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
