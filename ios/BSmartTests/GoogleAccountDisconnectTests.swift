import XCTest
@testable import BSmart

@MainActor
final class GoogleAccountDisconnectTests: XCTestCase {
    func testOnlyMatchingSDKIdentityCanDisconnect() async throws {
        let sdk = DisconnectTestSDK()
        let gate = GoogleIdentityOperationGate()
        let disconnect = NativeGoogleAccountDisconnector(sdk: sdk, gate: gate)
        for user in ["", "other"] {
            do { try await disconnect.disconnect(userID: user); XCTFail() }
            catch { XCTAssertEqual(error as? AccountDeletionError, .providerDisconnectRequired) }
        }
        XCTAssertEqual(sdk.calls, 0)
        let task = Task { try await disconnect.disconnect(userID: "matching") }
        try await sdk.waitForRequest()
        XCTAssertThrowsError(try gate.begin())
        sdk.callback?(nil)
        try await task.value
        let next = try gate.begin(); gate.finish(next)
    }

    func testTimeoutKeepsGateUntilLateCallbackThenOldCallbackCannotUnlockNewOperation() async throws {
        let sdk = DisconnectTestSDK()
        let gate = GoogleIdentityOperationGate()
        let disconnect = NativeGoogleAccountDisconnector(sdk: sdk, gate: gate, timeout: .milliseconds(20))
        do { try await disconnect.disconnect(userID: "matching"); XCTFail() }
        catch { XCTAssertEqual(error as? AccountDeletionError, .providerDisconnectRequired) }
        XCTAssertThrowsError(try gate.begin())
        let old = try XCTUnwrap(sdk.callback)
        old(nil)
        let new = try gate.begin()
        old(nil)
        XCTAssertThrowsError(try gate.begin())
        gate.finish(new)
        XCTAssertNoThrow(try gate.begin())
    }

    func testCancellationDoesNotUnlockLiveSDKOperationAndErrorIsRedacted() async throws {
        let sdk = DisconnectTestSDK()
        let gate = GoogleIdentityOperationGate()
        let disconnect = NativeGoogleAccountDisconnector(sdk: sdk, gate: gate)
        let task = Task { try await disconnect.disconnect(userID: "matching") }
        try await sdk.waitForRequest()
        task.cancel()
        do { try await task.value; XCTFail() } catch is CancellationError {} catch { XCTFail() }
        XCTAssertThrowsError(try gate.begin())
        sdk.callback?(NSError(domain: "private-token", code: 1))
        let next = try gate.begin(); gate.finish(next)
        let failing = Task { try await disconnect.disconnect(userID: "matching") }
        try await sdk.waitForRequest(count: 2)
        sdk.callback?(NSError(domain: "private-token", code: 1))
        do { try await failing.value; XCTFail() }
        catch {
            XCTAssertEqual(error as? AccountDeletionError, .providerDisconnectRequired)
            XCTAssertFalse(String(reflecting: error).contains("private-token"))
        }
    }

    func testAlreadyCancelledCallerDoesNotInvokeSDK() async throws {
        let sdk = DisconnectTestSDK()
        let disconnect = NativeGoogleAccountDisconnector(sdk: sdk, gate: GoogleIdentityOperationGate())
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await disconnect.disconnect(userID: "matching")
        }
        do { try await task.value; XCTFail() } catch is CancellationError {} catch { XCTFail() }
        XCTAssertEqual(sdk.calls, 0)
    }
}

@MainActor
private final class DisconnectTestSDK: GoogleDisconnectSDK {
    var currentUserID: String? = "matching"
    var callback: (@MainActor (Error?) -> Void)?
    var calls = 0
    func disconnect(completion: @escaping @MainActor (Error?) -> Void) { calls += 1; callback = completion }
    func waitForRequest(count: Int = 1) async throws {
        for _ in 0..<1000 {
            if calls >= count { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw AccountDeletionError.unavailable
    }
}
