import Foundation
import GoogleSignIn

@MainActor
final class GoogleIdentityOperationGate {
    static let shared = GoogleIdentityOperationGate()
    private var lease: UUID?
    func begin() throws -> UUID {
        guard lease == nil else { throw AccountDeletionError.providerDisconnectRequired }
        let id = UUID(); lease = id; return id
    }
    func finish(_ id: UUID) { if lease == id { lease = nil } }
}

@MainActor
protocol GoogleDisconnectSDK {
    var currentUserID: String? { get }
    func disconnect(completion: @escaping @MainActor (Error?) -> Void)
}

@MainActor
private struct SystemGoogleDisconnectSDK: GoogleDisconnectSDK {
    var currentUserID: String? { GIDSignIn.sharedInstance.currentUser?.userID }
    func disconnect(completion: @escaping @MainActor (Error?) -> Void) {
        GIDSignIn.sharedInstance.disconnect { error in
            Task { @MainActor in completion(error) }
        }
    }
}

@MainActor
final class NativeGoogleAccountDisconnector: GoogleAccountDisconnecting {
    private let sdk: GoogleDisconnectSDK
    private let gate: GoogleIdentityOperationGate
    private let timeout: Duration
    init(sdk: GoogleDisconnectSDK? = nil, gate: GoogleIdentityOperationGate? = nil, timeout: Duration = .seconds(10)) {
        self.sdk = sdk ?? SystemGoogleDisconnectSDK(); self.gate = gate ?? .shared; self.timeout = timeout
    }

    func disconnect(userID: String) async throws {
        try Task.checkCancellation()
        guard !userID.isEmpty, sdk.currentUserID == userID else { throw AccountDeletionError.providerDisconnectRequired }
        let lease = try gate.begin()
        let attempt = GoogleDisconnectAttempt(gate: gate, lease: lease)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                attempt.start(continuation, timeout: timeout)
                sdk.disconnect { error in attempt.received(error) }
            }
        } onCancel: {
            Task { @MainActor in attempt.cancel() }
        }
    }
}

@MainActor
private final class GoogleDisconnectAttempt {
    private let gate: GoogleIdentityOperationGate
    private let lease: UUID
    private var continuation: CheckedContinuation<Void, Error>?
    private var timer: Task<Void, Never>?
    private var cancelled = false
    init(gate: GoogleIdentityOperationGate, lease: UUID) { self.gate = gate; self.lease = lease }
    func start(_ continuation: CheckedContinuation<Void, Error>, timeout: Duration) {
        self.continuation = continuation
        if cancelled { finish(.failure(CancellationError())); return }
        timer = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.finish(.failure(AccountDeletionError.providerDisconnectRequired))
        }
    }
    func received(_ error: Error?) {
        gate.finish(lease)
        finish(error == nil ? .success(()) : .failure(AccountDeletionError.providerDisconnectRequired))
    }
    func cancel() {
        cancelled = true
        finish(.failure(CancellationError()))
    }
    private func finish(_ result: Result<Void, Error>) {
        timer?.cancel(); timer = nil
        let pending = continuation; continuation = nil
        pending?.resume(with: result)
        // SDK disconnect cannot be cancelled. Keep the gate until its real callback.
    }
}
