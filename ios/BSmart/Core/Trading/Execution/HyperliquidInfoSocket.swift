import Foundation
import CoreFoundation

protocol HyperliquidInfoSocket: Sendable {
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close()
}

enum HyperliquidInfoSocketError: Error {
    case unavailable, invalidResponse, rejected
}

// Only public info requests use this channel. Signed actions keep the one-shot broadcaster.
actor HyperliquidInfoConnection {
    static let shared = HyperliquidInfoConnection()
    private struct Pending {
        let type: String
        let limit: Int
        let continuation: CheckedContinuation<Data, Error>
        let timeout: Task<Void, Never>
        let sending: Task<Void, Never>
    }
    private let makeSocket: @Sendable () -> any HyperliquidInfoSocket
    private let timeout: Duration
    private let cooldown: Duration
    private var socket: (any HyperliquidInfoSocket)?
    private var receiving: Task<Void, Never>?
    private var generation = UUID()
    private var nextID = 0
    private var pending: [Int: Pending] = [:]
    private var retryAfter: ContinuousClock.Instant?

    init(timeout: Duration = .milliseconds(1200), cooldown: Duration = .seconds(60),
         makeSocket: @escaping @Sendable () -> any HyperliquidInfoSocket = { HyperliquidNativeInfoSocket() }) {
        self.timeout = timeout; self.cooldown = cooldown; self.makeSocket = makeSocket
    }

    deinit {
        receiving?.cancel(); socket?.close()
        for value in pending.values {
            value.timeout.cancel(); value.sending.cancel()
            value.continuation.resume(throwing: CancellationError())
        }
    }

    func read(_ query: HyperliquidExecutionQuery) async throws -> Data {
        try Task.checkCancellation()
        if case .fills = query { throw HyperliquidInfoSocketError.unavailable }
        let body = try query.body()
        guard let payload = try JSONSerialization.jsonObject(with: body) as? [String: String],
              let type = payload["type"] else { throw HyperliquidInfoSocketError.invalidResponse }
        // Large history responses keep using the existing bounded HTTP transport.
        guard type != "userFillsByTime", pending.count < 16,
              retryAfter.map({ ContinuousClock.now >= $0 }) ?? true else {
            throw HyperliquidInfoSocketError.unavailable
        }
        if socket == nil { connect() }
        guard let socket else { throw HyperliquidInfoSocketError.unavailable }
        nextID += 1
        let id = nextID, current = generation
        let envelope = try JSONSerialization.data(withJSONObject: [
            "method": "post", "id": id, "request": ["type": "info", "payload": payload]
        ])
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let timer = Task { [weak self, timeout] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    await self?.disconnect(generation: current)
                }
                let sending = Task { [weak self] in
                    do { try await socket.send(envelope) }
                    catch { if !Task.isCancelled { await self?.disconnect(generation: current) } }
                }
                pending[id] = .init(type: type, limit: 1_048_576, continuation: continuation,
                                    timeout: timer, sending: sending)
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    private func connect() {
        generation = UUID()
        let current = generation, socket = makeSocket()
        self.socket = socket
        receiving = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let data = try await socket.receive()
                    await self?.receive(data, generation: current)
                }
            } catch { await self?.disconnect(generation: current) }
        }
    }

    private func receive(_ data: Data, generation current: UUID) {
        guard current == generation else { return }
        guard data.count <= 1_049_600,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["channel"] as? String == "post",
              let responseData = json["data"] as? [String: Any],
              let rawID = responseData["id"] as? NSNumber,
              CFGetTypeID(rawID) != CFBooleanGetTypeID(),
              rawID.doubleValue == Double(rawID.intValue),
              let response = responseData["response"] as? [String: Any] else {
            disconnect(generation: current, error: HyperliquidInfoSocketError.invalidResponse)
            return
        }
        let id = rawID.intValue
        // A cancelled request may still have a response in flight.
        guard let value = pending[id] else { return }
        if response["type"] as? String == "error" {
            let status = (response["payload"] as? String).flatMap { Int($0.prefix(3)) }
            let failure: HyperliquidInfoSocketError = status.map { (500...599).contains($0) } == true ? .unavailable : .rejected
            finish(id: id, result: .failure(failure))
            return
        }
        guard response["type"] as? String == "info",
              let payload = response["payload"] as? [String: Any], payload["type"] as? String == value.type,
              let contents = payload["data"],
              let decoded = try? JSONSerialization.data(withJSONObject: contents, options: [.fragmentsAllowed]),
              decoded.count <= value.limit else {
            disconnect(generation: current, error: HyperliquidInfoSocketError.invalidResponse)
            return
        }
        finish(id: id, result: .success(decoded))
    }

    private func finish(id: Int, result: Result<Data, Error>) {
        guard let value = pending.removeValue(forKey: id) else { return }
        value.timeout.cancel(); value.sending.cancel()
        value.continuation.resume(with: result)
    }

    private func cancel(id: Int) { finish(id: id, result: .failure(CancellationError())) }

    private func disconnect(generation current: UUID, error: Error = HyperliquidInfoSocketError.unavailable) {
        guard current == generation else { return }
        generation = UUID()
        receiving?.cancel(); receiving = nil
        socket?.close(); socket = nil
        retryAfter = pending.isEmpty ? nil : .now.advanced(by: cooldown)
        for id in Array(pending.keys) { finish(id: id, result: .failure(error)) }
    }
}

private final class HyperliquidNativeInfoSocket: HyperliquidInfoSocket, @unchecked Sendable {
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.urlCredentialStorage = nil; config.httpCookieStorage = nil
        config.httpShouldSetCookies = false; config.httpAdditionalHeaders = nil
        config.waitsForConnectivity = false
        session = URLSession(configuration: config, delegate: InfoSocketNoRedirects(), delegateQueue: nil)
        task = session.webSocketTask(with: URL(string: "wss://api.hyperliquid.xyz/ws")!)
        task.maximumMessageSize = 1_049_600
        task.resume()
    }
    func send(_ data: Data) async throws {
        guard let text = String(data: data, encoding: .utf8) else { throw HyperliquidInfoSocketError.invalidResponse }
        try await task.send(.string(text))
    }
    func receive() async throws -> Data {
        switch try await task.receive() {
        case .data(let data): return data
        case .string(let string): return Data(string.utf8)
        @unknown default: throw HyperliquidInfoSocketError.invalidResponse
        }
    }
    func close() { task.cancel(with: .goingAway, reason: nil); session.invalidateAndCancel() }
    deinit { close() }
}

private final class InfoSocketNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
