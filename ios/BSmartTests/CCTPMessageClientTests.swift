import XCTest
@testable import BSmart

final class CCTPMessageClientTests: XCTestCase {
    private let sourceHash = "0x" + String(repeating: "ab", count: 32)

    func testSignedMessageNonceAndPendingResponseShapes() throws {
        let vector = try AttestationVector.load()
        let expected = CCTPMessageResult.complete(try vector.proof(), forwardHash: nil)
        XCTAssertEqual(try CCTPMessageClient.decode(vector.response(hash: sourceHash), transactionHash: sourceHash), expected)
        let decimal = try FundingQuantity(abi: vector.proof().nonce).formatted(decimals: 0)
        XCTAssertEqual(try CCTPMessageClient.decode(vector.response(hash: sourceHash, row: ["eventNonce": decimal]), transactionHash: sourceHash), expected)
        for emptyMessage: Any in [NSNull(), "0x"] {
            XCTAssertEqual(try CCTPMessageClient.decode(vector.response(hash: sourceHash, row:
                ["status": "pending_confirmations", "attestation": "PENDING", "message": emptyMessage]), transactionHash: sourceHash), .waiting)
        }
    }

    func testWrongIdentityMultiplicityVersionMalformedOrContradictoryResponsesFail() throws {
        let vector = try AttestationVector.load()
        for data in [try vector.response(hash: String(repeating: "0", count: 66)),
                     try vector.response(hash: sourceHash, count: 0), try vector.response(hash: sourceHash, count: 2)] {
            XCTAssertThrowsError(try CCTPMessageClient.decode(data, transactionHash: sourceHash))
        }
        for overrides: [String: Any] in [
            ["cctpVersion": 1], ["status": "unknown"], ["eventNonce": "9682"],
            ["eventNonce": "1e20"], ["eventNonce": "-1"], ["eventNonce": String(repeating: "9", count: 78)],
            ["eventNonce": "0x1"], ["eventNonce": "01"], ["eventNonce": NSNull()],
            ["message": "0x"], ["attestation": "PENDING"], ["forwardTxHash": "untrusted-url"],
            ["status": "pending_confirmations"], ["status": "pending_confirmations", "message": "0x", "attestation": NSNull()]
        ] {
            XCTAssertThrowsError(try CCTPMessageClient.decode(vector.response(hash: sourceHash, row: overrides), transactionHash: sourceHash))
        }
        XCTAssertThrowsError(try CCTPMessageClient.decode(Data(repeating: 32, count: 32_769), transactionHash: sourceHash))
    }

    func testHTTPOnlySendsSourceHashNoCredentialsAndStrictNotFound() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AttestationURLProtocol.self]
        config.httpAdditionalHeaders = ["Authorization": "must-not-leave-device", "Cookie": "private"]
        let client = CCTPMessageClient(configuration: config)
        let vector = try AttestationVector.load()
        AttestationURLProtocol.setResponse(status: 200, data: try vector.response(hash: sourceHash))
        let result = try await client.message(transactionHash: sourceHash)
        XCTAssertEqual(result, .complete(try vector.proof(), forwardHash: nil))
        let request = try XCTUnwrap(AttestationURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://iris-api.circle.com/v2/messages/3?transactionHash=" + sourceHash)
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertNotNil(config.httpAdditionalHeaders?["Authorization"])
        AttestationURLProtocol.setResponse(status: 404, data: Data(#"{"code":404,"message":"Not found."}"#.utf8))
        let pending = try await client.message(transactionHash: sourceHash)
        XCTAssertEqual(pending, .waiting)
    }

    func testHTTPFailureRedirectOversizeOrInvalid404NeverMeansWaiting() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AttestationURLProtocol.self]
        let client = CCTPMessageClient(configuration: config)
        for (status, type, data) in [(302, "application/json", Data()), (429, "application/json", Data()),
                                    (500, "application/json", Data()), (200, "text/html", Data()),
                                    (404, "application/json", Data("{}".utf8)),
                                    (200, "application/json", Data(repeating: 32, count: 32_769))] {
            AttestationURLProtocol.setResponse(status: status, type: type, data: data)
            do { _ = try await client.message(transactionHash: sourceHash); XCTFail("Accepted \(status)") }
            catch { XCTAssertEqual(error as? FundingObservationError, .unavailable) }
        }
    }
}

private final class AttestationURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var payload: (Int, String, Data) = (500, "application/json", Data())
    private static var captured: URLRequest?
    static var lastRequest: URLRequest? { lock.withLock { captured } }
    static func setResponse(status: Int, type: String = "application/json", data: Data) {
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
