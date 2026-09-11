import AuthenticationServices
import XCTest
@testable import BSmart

@MainActor
final class AppleCredentialStateTests: XCTestCase {
    func testEveryExplicitSystemStateIsMappedWithoutInventingAuthorization() async throws {
        for (state, expected) in [(ASAuthorizationAppleIDProvider.CredentialState.authorized, AppleCredentialStatus.authorized),
                                  (.revoked, .revoked), (.notFound, .notFound), (.transferred, .transferred)] {
            let client = NativeAppleCredentialStateClient { userID, completion in
                XCTAssertEqual(userID, "opaque-apple-user")
                completion(state, nil)
            }
            let result = try await client.check(userID: "opaque-apple-user")
            XCTAssertEqual(result, expected)
        }
    }

    func testMissingAndMalformedIdentifiersNeverQueryTheSystem() async throws {
        let client = NativeAppleCredentialStateClient { _, _ in XCTFail("Invalid identifier reached Apple") }
        for value in [nil, "", "apple\nuser", "apple user", String(repeating: "a", count: 256)] {
            let result = try await client.check(userID: value)
            XCTAssertEqual(result, .notFound)
        }
    }

    func testAnErrorAlongsideAnyStateIsUnavailableNotAuthorizationOrRevocation() async {
        for state in [ASAuthorizationAppleIDProvider.CredentialState.notFound, .authorized, .revoked, .transferred] {
            let client = NativeAppleCredentialStateClient { _, completion in
                completion(state, NSError(domain: "opaque-user-secret", code: -1))
            }
            do { _ = try await client.check(userID: "opaque-apple-user"); XCTFail("Error accepted as a state") }
            catch AccountAccessError.credentialUnavailable {} catch { XCTFail("Unexpected error") }
        }
    }

    func testTimeoutReturnsAndLateDuplicateCallbacksDoNotResumeAgain() async throws {
        var reply: NativeAppleCredentialStateClient.Completion?
        let client = NativeAppleCredentialStateClient(timeout: .milliseconds(10)) { _, callback in reply = callback }
        do { _ = try await client.check(userID: "opaque-apple-user"); XCTFail("Unanswered lookup accepted") }
        catch AccountAccessError.credentialUnavailable {} catch { XCTFail("Unexpected error") }
        let callback = try XCTUnwrap(reply)
        callback(.authorized, nil)
        callback(.revoked, nil)
        try await Task.sleep(for: .milliseconds(10))
    }

    func testCancellationEndsLookupWithoutWaitingForTheSystemAndIgnoresLateAuthorization() async throws {
        var reply: NativeAppleCredentialStateClient.Completion?
        let client = NativeAppleCredentialStateClient { _, callback in reply = callback }
        let request = Task { try await client.check(userID: "opaque-apple-user") }
        for _ in 0..<500 {
            if reply != nil { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        let callback = try XCTUnwrap(reply)
        request.cancel()
        do { _ = try await request.value; XCTFail("Cancelled lookup returned authorization") }
        catch is CancellationError {} catch { XCTFail("Unexpected error") }
        callback(.authorized, nil)
        try await Task.sleep(for: .milliseconds(10))
    }

    func testConcurrentMonitorChecksShareOneLookupAndInvalidateTogether() async throws {
        let client = ControlledAppleCredentialState()
        client.suspended = true
        let now = Date()
        let monitor = AppleCredentialMonitor(client: client, now: { now })
        let first = Task { try await monitor.authorize(userID: "opaque-apple-user") }
        try await client.waitForRequest()
        let second = Task { try await monitor.authorize(userID: "opaque-apple-user") }
        try await Task.sleep(for: .milliseconds(10))
        monitor.invalidate()
        client.finish(.authorized)
        for request in [first, second] {
            do { _ = try await request.value; XCTFail("Invalidated check returned permission") } catch {}
        }
        XCTAssertEqual(client.requests, ["opaque-apple-user"])
        client.suspended = false
        let authorization = try await monitor.authorize(userID: "opaque-apple-user")
        XCTAssertEqual(authorization.expiresAt, now.addingTimeInterval(60))
    }

    func testAuthorizationsAndErrorsAreNotReusedAfterACompletedMonitorRequest() async throws {
        let client = ControlledAppleCredentialState()
        let monitor = AppleCredentialMonitor(client: client, now: Date.init)
        _ = try await monitor.authorize(userID: "opaque-apple-user")
        client.result = .revoked
        do { _ = try await monitor.authorize(userID: "opaque-apple-user"); XCTFail("Old authorization reused") }
        catch AccountAccessError.expired {} catch { XCTFail("Unexpected error") }
        client.result = .authorized
        _ = try await monitor.authorize(userID: "opaque-apple-user")
        XCTAssertEqual(client.requests.count, 3)
    }

    func testAuthorizationRequiresBothWallAndContinuousTimeWithinOriginalWindow() {
        let now = Date()
        let instant = ContinuousClock.now
        let authorization = AppleCredentialAuthorization(checkedAt: now, checkedInstant: instant)
        for (wallSeconds, elapsedSeconds, expected) in [(0.0, 0, true), (59.0, 59, true),
            (-1.0, 1, false), (60.0, 1, false), (1.0, 60, false), (0.0, -1, false)] {
            XCTAssertEqual(authorization.isValid(now: now.addingTimeInterval(wallSeconds),
                instant: instant.advanced(by: .seconds(elapsedSeconds))), expected)
        }
    }
}

final class CredentialMonotonicTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant = ContinuousClock.now
    var now: ContinuousClock.Instant { lock.lock(); defer { lock.unlock() }; return instant }
    func advance(_ seconds: Int) {
        lock.lock(); defer { lock.unlock() }
        instant = instant.advanced(by: .seconds(seconds))
    }
}

@MainActor
final class ControlledAppleCredentialState: AppleCredentialStateChecking {
    var result: AppleCredentialStatus = .authorized
    var fails = false
    var suspended = false
    private(set) var requests: [String?] = []
    private var pending: CheckedContinuation<AppleCredentialStatus, Error>?

    func check(userID: String?) async throws -> AppleCredentialStatus {
        requests.append(userID)
        if fails { throw AccountAccessError.credentialUnavailable }
        if suspended { return try await withCheckedThrowingContinuation { pending = $0 } }
        return result
    }

    func waitForRequest() async throws {
        for _ in 0..<500 {
            if pending != nil { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw AccountAccessError.unavailable
    }

    func finish(_ result: AppleCredentialStatus) {
        guard let pending else { XCTFail("No pending native check"); return }
        self.pending = nil
        suspended = false
        self.result = result
        pending.resume(returning: result)
    }
}
