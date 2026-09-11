import XCTest
@testable import BSmart

final class ArbitrumFundingBroadcastTests: XCTestCase {
    func testStrictResponseOnlyAcknowledgesExactLocalHash() throws {
        let id = UUID().uuidString
        let hash = "0x" + String(repeating: "ab", count: 32)
        let correct: [String: Any] = ["jsonrpc": "2.0", "id": id, "result": hash]
        let data = try JSONSerialization.data(withJSONObject: correct)
        XCTAssertEqual(ArbitrumFundingBroadcaster.outcome(data, id: id, hash: hash), .nodeAcknowledged(hash))
        for malformed in [
            [:], ["jsonrpc": "1.0", "id": id, "result": hash], ["jsonrpc": "2.0", "id": "wrong", "result": hash],
            ["jsonrpc": "2.0", "id": id, "result": NSNull()], ["jsonrpc": "2.0", "id": id, "result": "0x0"],
            ["jsonrpc": "2.0", "id": id, "result": hash, "error": NSNull()],
            ["jsonrpc": "2.0", "id": id, "error": ["code": -32000, "message": "already known"]],
            ["jsonrpc": "2.0", "id": 1, "result": hash], ["jsonrpc": "2.0", "id": id, "result": hash.uppercased()]
        ] as [[String: Any]] {
            XCTAssertEqual(ArbitrumFundingBroadcaster.outcome(try JSONSerialization.data(withJSONObject: malformed), id: id, hash: hash), .uncertain)
        }
        XCTAssertEqual(ArbitrumFundingBroadcaster.outcome(Data(repeating: 32, count: 16_385), id: id, hash: hash), .uncertain)
        XCTAssertEqual(ArbitrumFundingBroadcaster.outcome(try JSONSerialization.data(withJSONObject: [correct]), id: id, hash: hash), .uncertain)
    }

    func testTransportSendsOnlyJournaledBytesWithoutCredentialsAndCannotRepeat() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (permit, signed) = try await makePermit(context)
        SubmissionURLProtocol.configure(mode: .success, hash: signed.hash)
        let client = client()
        let lease = FundingSigningLease(wallet: context.wallet, clock: { context.clock.now })
        let outcome = try await client.submit(permit, lease: lease)
        XCTAssertEqual(outcome, .nodeAcknowledged(signed.hash))
        let request = try XCTUnwrap(SubmissionURLProtocol.captured)
        XCTAssertEqual(request.url, ArbitrumFundingRPC.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        let payload = try XCTUnwrap(SubmissionURLProtocol.payload)
        XCTAssertEqual(payload["method"] as? String, "eth_sendRawTransaction")
        XCTAssertEqual(payload["params"] as? [String], [FundingHex.encode(signed.raw)])
        XCTAssertEqual(Set(payload.keys), ["jsonrpc", "id", "method", "params"])
        let copiedReference = permit
        await expectJournalFailure { try await client.submit(copiedReference, lease: lease) }
        XCTAssertEqual(SubmissionURLProtocol.count, 1)
        let records = try await context.journal().records(wallet: context.wallet)
        XCTAssertEqual(records.first?.state, .submitting) // Transport itself cannot declare execution or mutate funds.
    }

    func testFailuresAreUncertainAndNeverRetry() async throws {
        for mode in [SubmissionURLProtocol.Mode.timeout, .wrongHash, .rpcError, .redirect, .html, .rateLimit, .oversized] {
            let context = FundingJournalTestContext(); defer { context.cleanup() }
            let (permit, signed) = try await makePermit(context)
            SubmissionURLProtocol.configure(mode: mode, hash: signed.hash)
            let client = client()
            let lease = FundingSigningLease(wallet: context.wallet, clock: { context.clock.now })
            let result = try await client.submit(permit, lease: lease)
            XCTAssertEqual(result, .uncertain, "\(mode)")
            await expectJournalFailure { try await client.submit(permit, lease: lease) }
            XCTAssertEqual(SubmissionURLProtocol.count, 1)
        }
    }

    func testExpiredRevokedOtherAccountAndLegacyPermitsCannotStartTask() async throws {
        for mode in 0..<4 {
            let context = FundingJournalTestContext(); defer { context.cleanup() }
            let (permit, signed) = try await makePermit(context, consent: mode != 3)
            SubmissionURLProtocol.configure(mode: .success, hash: signed.hash)
            let wallet = mode == 2
                ? DeviceWalletSummary(accountID: UUID(), address: context.wallet.address, recoveryVerified: true) : context.wallet
            let lease = FundingSigningLease(wallet: wallet, clock: { context.clock.now })
            if mode == 0 { context.clock.advance(10) }
            if mode == 1 { lease.invalidate() }
            await expectJournalFailure { try await self.client().submit(permit, lease: lease) }
            XCTAssertEqual(SubmissionURLProtocol.count, 0)
            // Failed first use cannot be revived with a new account/foreground lease.
            let renewed = FundingSigningLease(wallet: context.wallet, clock: { context.clock.now })
            await expectJournalFailure { try await self.client().submit(permit, lease: renewed) }
        }
    }

    func testConcurrentUseStartsOneTask() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (permit, signed) = try await makePermit(context)
        SubmissionURLProtocol.configure(mode: .success, hash: signed.hash)
        let client = client()
        let lease = FundingSigningLease(wallet: context.wallet, clock: { context.clock.now })
        let accepted = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 { group.addTask { (try? await client.submit(permit, lease: lease)) == .nodeAcknowledged(signed.hash) } }
            var count = 0
            for await result in group { if result { count += 1 } }
            return count
        }
        XCTAssertEqual(accepted, 1)
        XCTAssertEqual(SubmissionURLProtocol.count, 1)
    }

    func testCancellationBeforeStartCannotSend() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (permit, signed) = try await makePermit(context)
        SubmissionURLProtocol.configure(mode: .success, hash: signed.hash)
        let client = client()
        let lease = FundingSigningLease(wallet: context.wallet, clock: { context.clock.now })
        let stopped = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try await client.submit(permit, lease: lease); return false }
            catch { return true }
        }.value
        XCTAssertTrue(stopped)
        XCTAssertEqual(SubmissionURLProtocol.count, 0)
    }

    func testStartedURLSessionStillReturnsEvidenceAfterCancellationAndLeaseRevocation() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (permit, signed) = try await makePermit(context)
        let started = expectation(description: "Network task received the signed transaction")
        SubmissionURLProtocol.configure(mode: .success, hash: signed.hash, heldUntilRelease: started)
        let client = client()
        let lease = FundingSigningLease(wallet: context.wallet, clock: { context.clock.now })
        let task = Task { try await client.submit(permit, lease: lease) }
        await fulfillment(of: [started], timeout: 5)
        task.cancel()
        lease.invalidate()
        SubmissionURLProtocol.releaseResponse()
        let result = try await task.value
        XCTAssertEqual(result, .nodeAcknowledged(signed.hash))
        XCTAssertEqual(SubmissionURLProtocol.count, 1)
    }

    private func client() -> ArbitrumFundingBroadcaster {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SubmissionURLProtocol.self]
        config.httpAdditionalHeaders = ["Authorization": "must-not-leave", "Cookie": "must-not-leave"]
        return .init(configuration: config)
    }

    private func makePermit(_ context: FundingJournalTestContext, consent: Bool = true) async throws -> (FundingSubmissionPermit, CCTPSignedSourceTransaction) {
        let journal = try context.journal()
        let transaction = try await context.transaction()
        let id = UUID()
        let signed = try await consent ? context.readyWithConsent(transaction, id: id, journal: journal)
                                      : context.ready(transaction, id: id, journal: journal)
        let check = try await context.recordedSubmissionCheck(signed)
        return (try await journal.beginSubmission(id: id, signed: signed, wallet: context.wallet, check: check), signed)
    }
}

private final class SubmissionURLProtocol: URLProtocol, @unchecked Sendable {
    enum Mode { case success, timeout, wrongHash, rpcError, redirect, html, rateLimit, oversized }
    private static let lock = NSLock()
    private static var mode = Mode.success
    private static var hash = ""
    private static var requestCount = 0
    private static var request: URLRequest?
    private static var body: [String: Any]?
    private static var started: XCTestExpectation?
    private static var heldResponse: (() -> Void)?
    static var captured: URLRequest? { lock.lock(); defer { lock.unlock() }; return request }
    static var payload: [String: Any]? { lock.lock(); defer { lock.unlock() }; return body }
    static var count: Int { lock.lock(); defer { lock.unlock() }; return requestCount }
    static func configure(mode: Mode, hash: String, heldUntilRelease: XCTestExpectation? = nil) {
        lock.lock(); defer { lock.unlock() }
        self.mode = mode; self.hash = hash; requestCount = 0; request = nil; body = nil
        started = heldUntilRelease; heldResponse = nil
    }
    static func releaseResponse() {
        lock.lock()
        let callback = heldResponse; heldResponse = nil
        lock.unlock()
        callback?()
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 4_096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    guard count > 0 else { break }
                    data.append(contentsOf: bytes.prefix(count))
                }
            }
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            Self.lock.lock()
            Self.request = request; Self.body = payload; Self.requestCount += 1
            let mode = Self.mode; let hash = Self.hash
            Self.lock.unlock()
            if mode == .timeout { throw URLError(.timedOut) }
            let result: [String: Any] = mode == .rpcError
                ? ["jsonrpc": "2.0", "id": payload["id"]!, "error": ["code": -32000, "message": "already known"]]
                : ["jsonrpc": "2.0", "id": payload["id"]!, "result": mode == .wrongHash ? "0x" + String(repeating: "00", count: 32) : hash]
            let bytes = mode == .oversized ? Data(repeating: 32, count: 16_385) : try JSONSerialization.data(withJSONObject: result)
            let response = try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: mode == .redirect ? 302 : mode == .rateLimit ? 429 : 200,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mode == .html ? "text/html" : "application/json"]))
            let deliver = {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: bytes)
                self.client?.urlProtocolDidFinishLoading(self)
            }
            Self.lock.lock()
            let started = Self.started
            if started != nil { Self.heldResponse = deliver }
            Self.lock.unlock()
            if let started { started.fulfill() }
            else { deliver() }
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
