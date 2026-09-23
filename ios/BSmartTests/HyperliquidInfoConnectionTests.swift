import XCTest
@testable import BSmart

final class HyperliquidInfoConnectionTests: XCTestCase {
    func testConcurrentQueriesUseOneConnectionAndMatchOutOfOrderReplies() async throws {
        let socket = InfoSocketStub()
        let connection = HyperliquidInfoConnection(makeSocket: { socket })
        let first = Task { try await connection.read(.dexs) }
        let second = Task { try await connection.read(.metadata(dex: "xyz")) }
        try await waitForRequests(2, socket)
        for request in socket.sent.reversed() { try socket.reply(request, value: ["observed": request.type]) }
        let values = try await [first.value, second.value]
        let types = try values.map { try JSONSerialization.jsonObject(with: $0) as? [String: String] }
        XCTAssertEqual(types[0]?["observed"], "perpDexs")
        XCTAssertEqual(types[1]?["observed"], "meta")
        XCTAssertEqual(Set(socket.sent.map(\.id)).count, 2)
        XCTAssertTrue(socket.sent.allSatisfy { $0.method == "post" && $0.kind == "info" })
    }

    func testScalarAndNullPayloadsRemainValidJSON() async throws {
        for value: Any in ["unifiedAccount", NSNull()] {
            let socket = InfoSocketStub()
            let connection = HyperliquidInfoConnection(makeSocket: { socket })
            let task = Task { try await connection.read(.mode(owner: HyperliquidTradingFixture.wallet.address)) }
            try await waitForRequests(1, socket)
            try socket.reply(socket.sent[0], value: value)
            let bytes = try await task.value
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed]))
        }
    }

    func testMalformedAndWrongQueryRepliesFailClosed() async throws {
        for wrongType in [false, true] {
            let socket = InfoSocketStub()
            let connection = HyperliquidInfoConnection(makeSocket: { socket })
            let task = Task { try await connection.read(.dexs) }
            try await waitForRequests(1, socket)
            if wrongType { try socket.reply(socket.sent[0], value: [:], type: "userFees") }
            else { socket.feed(Data("not JSON".utf8)) }
            do { _ = try await task.value; XCTFail("Accepted a malformed reply") }
            catch { guard case HyperliquidInfoSocketError.invalidResponse = error else { return XCTFail("\(error)") } }
            XCTAssertTrue(socket.closed)
        }
    }

    func testServerRejectionIsNotRetried() async throws {
        let socket = InfoSocketStub()
        let connection = HyperliquidInfoConnection(makeSocket: { socket })
        let task = Task { try await connection.read(.dexs) }
        try await waitForRequests(1, socket)
        socket.feed(try JSONSerialization.data(withJSONObject: ["channel": "post", "data": [
            "id": socket.sent[0].id, "response": ["type": "error", "payload": "429"]]]))
        do { _ = try await task.value; XCTFail("Accepted rejection") }
        catch { guard case HyperliquidInfoSocketError.rejected = error else { return XCTFail("\(error)") } }
        XCTAssertEqual(socket.sent.count, 1)
    }

    func testServerOutageCanUseReadOnlyHTTPFallback() async throws {
        let socket = InfoSocketStub()
        let connection = HyperliquidInfoConnection(makeSocket: { socket })
        let task = Task { try await connection.read(.dexs) }
        try await waitForRequests(1, socket)
        socket.feed(try JSONSerialization.data(withJSONObject: ["channel": "post", "data": [
            "id": socket.sent[0].id, "response": ["type": "error", "payload": "503 Service Unavailable"]]]))
        do { _ = try await task.value; XCTFail("Accepted outage as market data") }
        catch { guard case HyperliquidInfoSocketError.unavailable = error else { return XCTFail("\(error)") } }
    }

    func testTimeoutFailsPendingReadsAndSuppressesRepeatedConnectionDelays() async throws {
        let socket = InfoSocketStub()
        let connection = HyperliquidInfoConnection(timeout: .milliseconds(50), makeSocket: { socket })
        do { _ = try await connection.read(.dexs); XCTFail("No timeout") }
        catch { guard case HyperliquidInfoSocketError.unavailable = error else { return XCTFail("\(error)") } }
        do { _ = try await connection.read(.dexs); XCTFail("No cooldown") }
        catch { guard case HyperliquidInfoSocketError.unavailable = error else { return XCTFail("\(error)") } }
        XCTAssertEqual(socket.sent.count, 1)
        XCTAssertTrue(socket.closed)
    }

    func testCancellingOneReadDoesNotCancelOtherReadsOrAcceptLateReplies() async throws {
        let socket = InfoSocketStub()
        let connection = HyperliquidInfoConnection(makeSocket: { socket })
        let first = Task { try await connection.read(.dexs) }
        try await waitForRequests(1, socket)
        let second = Task { try await connection.read(.metadata(dex: "xyz")) }
        try await waitForRequests(2, socket)
        first.cancel()
        do { _ = try await first.value; XCTFail("Cancellation lost") } catch { XCTAssertTrue(error is CancellationError) }
        try socket.reply(socket.sent[0], value: ["late": true])
        try socket.reply(socket.sent[1], value: ["current": true])
        let bytes = try await second.value
        XCTAssertEqual(try JSONSerialization.jsonObject(with: bytes) as? [String: Bool], ["current": true])
        XCTAssertFalse(socket.closed)
    }

    func testInvalidQueryCannotOpenASocket() async {
        let socket = InfoSocketStub()
        let connection = HyperliquidInfoConnection(makeSocket: { socket })
        do { _ = try await connection.read(.book(coin: "xyz:")); XCTFail("Invalid query") } catch {}
        XCTAssertTrue(socket.sent.isEmpty)
    }

    func testOversizedFrameFailsEveryPendingRead() async throws {
        let socket = InfoSocketStub()
        let connection = HyperliquidInfoConnection(makeSocket: { socket })
        let first = Task { try await connection.read(.dexs) }
        let second = Task { try await connection.read(.metadata(dex: "xyz")) }
        try await waitForRequests(2, socket)
        socket.feed(Data(repeating: 32, count: 1_049_601))
        for task in [first, second] {
            do { _ = try await task.value; XCTFail("Accepted oversized frame") }
            catch { guard case HyperliquidInfoSocketError.invalidResponse = error else { return XCTFail("\(error)") } }
        }
        XCTAssertTrue(socket.closed)
    }

    func testDisconnectedReadFailsAndEntersCooldown() async throws {
        let socket = InfoSocketStub()
        let connection = HyperliquidInfoConnection(makeSocket: { socket })
        let task = Task { try await connection.read(.dexs) }
        try await waitForRequests(1, socket)
        socket.close()
        do { _ = try await task.value; XCTFail("Disconnected read returned data") }
        catch { guard case HyperliquidInfoSocketError.unavailable = error else { return XCTFail("\(error)") } }
        do { _ = try await connection.read(.dexs); XCTFail("Disconnected socket reused") }
        catch { guard case HyperliquidInfoSocketError.unavailable = error else { return XCTFail("\(error)") } }
        XCTAssertEqual(socket.sent.count, 1)
    }

    private func waitForRequests(_ count: Int, _ socket: InfoSocketStub) async throws {
        for _ in 0..<100 {
            if socket.sent.count >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Missing socket requests")
        throw HyperliquidInfoSocketError.unavailable
    }
}

private final class InfoSocketStub: HyperliquidInfoSocket, @unchecked Sendable {
    struct Request {
        let id: Int
        let type, kind, method: String
    }
    private let lock = NSLock()
    private var requests: [Request] = []
    private var isClosed = false
    private let stream: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    var sent: [Request] { lock.withLock { requests } }
    var closed: Bool { lock.withLock { isClosed } }

    init() { (stream, continuation) = AsyncThrowingStream.makeStream(of: Data.self) }
    func send(_ data: Data) async throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let request = try XCTUnwrap(object["request"] as? [String: Any])
        let payload = try XCTUnwrap(request["payload"] as? [String: String])
        let row = try Request(id: XCTUnwrap(object["id"] as? Int), type: XCTUnwrap(payload["type"]),
            kind: XCTUnwrap(request["type"] as? String), method: XCTUnwrap(object["method"] as? String))
        lock.withLock { requests.append(row) }
    }
    func receive() async throws -> Data {
        var iterator = stream.makeAsyncIterator()
        guard let data = try await iterator.next() else { throw HyperliquidInfoSocketError.unavailable }
        return data
    }
    func close() {
        lock.withLock { isClosed = true }
        continuation.finish(throwing: HyperliquidInfoSocketError.unavailable)
    }
    func feed(_ data: Data) { continuation.yield(data) }
    func reply(_ request: Request, value: Any, type: String? = nil) throws {
        feed(try JSONSerialization.data(withJSONObject: ["channel": "post", "data": [
            "id": request.id, "response": ["type": "info", "payload": ["type": type ?? request.type, "data": value]]]]))
    }
}
