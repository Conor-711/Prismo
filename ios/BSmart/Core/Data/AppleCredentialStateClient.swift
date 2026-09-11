import AuthenticationServices
import Foundation

enum AppleCredentialStatus: Equatable { case authorized, revoked, notFound, transferred }

@MainActor
protocol AppleCredentialStateChecking {
    func check(userID: String?) async throws -> AppleCredentialStatus
}

@MainActor
struct NativeAppleCredentialStateClient: AppleCredentialStateChecking {
    typealias Completion = @Sendable (ASAuthorizationAppleIDProvider.CredentialState, Error?) -> Void
    typealias Lookup = (String, @escaping Completion) -> Void
    private let lookup: Lookup
    private let timeout: Duration

    init(timeout: Duration = .seconds(10), lookup: @escaping Lookup = { userID, completion in
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID, completion: completion)
    }) {
        self.timeout = timeout; self.lookup = lookup
    }

    func check(userID: String?) async throws -> AppleCredentialStatus {
        guard let userID, Self.validUserID(userID) else { return .notFound }
        let pending = AppleCredentialLookup()
        let result = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pending.start(continuation, timeout: timeout)
                lookup(userID) { state, error in
                    Task { @MainActor in pending.complete(state, error: error) }
                }
            }
        } onCancel: {
            Task { @MainActor in pending.finish(.failure(CancellationError())) }
        }
        try Task.checkCancellation()
        return result
    }

    static func validUserID(_ value: String) -> Bool {
        (1...255).contains(value.utf8.count) && value.utf8.allSatisfy { (33...126).contains($0) }
    }
}

@MainActor
private final class AppleCredentialLookup {
    private var continuation: CheckedContinuation<AppleCredentialStatus, Error>?
    private var deadline: Task<Void, Never>?

    func start(_ continuation: CheckedContinuation<AppleCredentialStatus, Error>, timeout: Duration) {
        self.continuation = continuation
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.finish(.failure(AccountAccessError.credentialUnavailable))
        }
    }

    func complete(_ state: ASAuthorizationAppleIDProvider.CredentialState, error: Error?) {
        // The SDK can report .notFound together with an error; that is not proof of revocation.
        guard error == nil else { finish(.failure(AccountAccessError.credentialUnavailable)); return }
        switch state {
        case .authorized: finish(.success(.authorized))
        case .revoked: finish(.success(.revoked))
        case .notFound: finish(.success(.notFound))
        case .transferred: finish(.success(.transferred))
        @unknown default: finish(.failure(AccountAccessError.credentialUnavailable))
        }
    }

    func finish(_ result: Result<AppleCredentialStatus, Error>) {
        let continuation = self.continuation
        self.continuation = nil
        deadline?.cancel()
        deadline = nil
        continuation?.resume(with: result)
    }
}
