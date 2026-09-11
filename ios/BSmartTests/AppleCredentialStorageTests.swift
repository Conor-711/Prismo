import XCTest
@testable import BSmart

@MainActor
final class AppleCredentialStorageTests: XCTestCase {
    func testLegacyAndVersionTwoSessionsRemainReadableWithoutAnInventedAppleUser() throws {
        let session = renewalSession(account: .init(id: UUID(), provider: .apple))
        let encoder = BSmartJSONCoding.makeEncoder()
        let legacy = try AccountSessionEnvelope.decode(encoder.encode(session))
        XCTAssertNil(legacy.appleUserID)
        let privateRecord = AccountSessionEnvelope(session: session, renewalPending: false, appleUserID: "opaque-apple-user")
        XCTAssertEqual(String(describing: privateRecord), "AccountSessionEnvelope(redacted)")
        XCTAssertEqual(String(reflecting: privateRecord), "AccountSessionEnvelope(redacted)")
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(
            AccountSessionEnvelope(session: session, renewalPending: false))) as? [String: Any])
        old["version"] = 2
        let decoded = try AccountSessionEnvelope.decode(JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(decoded.appleUserID)
        XCTAssertEqual(decoded.session.account, session.account)
        old["appleUserID"] = "not-a-version-two-field"
        XCTAssertThrowsError(try AccountSessionEnvelope.decode(JSONSerialization.data(withJSONObject: old)))
        old["version"] = 4
        XCTAssertThrowsError(try AccountSessionEnvelope.decode(JSONSerialization.data(withJSONObject: old)))
    }

    func testKeychainReferenceMovesOnlyWithTheExactPendingRenewalAndClearsOnFreshLogin() throws {
        let service = "test.bsmart.apple-state." + UUID().uuidString
        let storage = KeychainAccountSessionStore(service: service)
        defer { try? storage.clear() }
        let previous = renewalSession(account: .init(id: UUID(), provider: .apple))
        let next = renewalSession(account: previous.account, version: "replacement")
        try storage.save(previous, appleUserID: "opaque-apple-user")
        XCTAssertEqual(try storage.appleUserID(for: previous), "opaque-apple-user")
        XCTAssertThrowsError(try storage.appleUserID(for: next))
        XCTAssertThrowsError(try storage.completeRenewal(next, replacing: previous))
        try storage.beginRenewal(previous)
        let restored = KeychainAccountSessionStore(service: service)
        XCTAssertEqual(try restored.appleUserID(for: previous), "opaque-apple-user")
        XCTAssertThrowsError(try restored.completeRenewal(renewalSession(), replacing: previous))
        try restored.completeRenewal(next, replacing: previous)
        XCTAssertEqual(try storage.appleUserID(for: next), "opaque-apple-user")
        XCTAssertFalse(try storage.isRenewalPending())
        XCTAssertThrowsError(try storage.completeRenewal(next, replacing: previous))
        try storage.save(next)
        XCTAssertNil(try storage.appleUserID(for: next))
        let google = renewalSession()
        try storage.save(google)
        XCTAssertNil(try storage.appleUserID(for: google))
        try storage.clear()
        XCTAssertNil(try restored.load())
    }

    func testMalformedAndWrongProviderReferencesNeverReplaceExistingKeychainData() throws {
        let storage = KeychainAccountSessionStore(service: "test.bsmart.apple-state." + UUID().uuidString)
        defer { try? storage.clear() }
        let previous = renewalSession(account: .init(id: UUID(), provider: .apple))
        try storage.save(previous, appleUserID: "opaque-apple-user")
        for id in ["", "apple user", "apple\nuser", String(repeating: "a", count: 256)] {
            XCTAssertThrowsError(try storage.save(previous, appleUserID: id))
        }
        XCTAssertThrowsError(try storage.save(renewalSession(), appleUserID: "opaque-apple-user"))
        XCTAssertEqual(try storage.load(), previous)
        XCTAssertEqual(try storage.appleUserID(for: previous), "opaque-apple-user")
    }
}
