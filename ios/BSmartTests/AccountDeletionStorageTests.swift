import XCTest
import Security
@testable import BSmart

@MainActor
final class AccountDeletionStorageTests: XCTestCase {
    func testDeviceOnlyProtectionRestartAndNoRemovalOfUnfinishedRequest() throws {
        let service = "bsmart.deletion-test." + UUID().uuidString
        let query = keychainQuery(service)
        defer { SecItemDelete(query as CFDictionary) }
        let fixture = DeletionFixture()
        var record = try fixture.record()
        let storage = KeychainAccountDeletionStore(service: service)
        try storage.save(record)
        let restarted = KeychainAccountDeletionStore(service: service)
        XCTAssertEqual(try restarted.load(), record)
        var attributes = query
        attributes[kSecReturnAttributes as String] = true
        var value: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(attributes as CFDictionary, &value), errSecSuccess)
        let saved = try XCTUnwrap(value as? [String: Any])
        XCTAssertEqual(saved[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertEqual(saved[kSecAttrSynchronizable as String] as? Bool, false)
        try record.willSubmit(); try storage.save(record)
        XCTAssertThrowsError(try restarted.clear(ticket: fixture.ticket))
        try record.received(fixture.receipt(completed: true), now: fixture.now)
        try storage.save(record)
        try record.finishedProviderDisconnect(); try storage.save(record)
        try record.finishedLocalCleanup(); try storage.save(record)
        try restarted.clear(ticket: fixture.ticket)
        XCTAssertNil(try storage.load())
    }

    func testCorruptKeychainFailsClosedWithoutOverwriteOrRemoval() throws {
        let service = "bsmart.deletion-test." + UUID().uuidString
        let query = keychainQuery(service)
        defer { SecItemDelete(query as CFDictionary) }
        let corrupt = Data("not a record".utf8)
        let insert = query.merging([kSecValueData as String: corrupt]) { _, new in new }
        XCTAssertEqual(SecItemAdd(insert as CFDictionary, nil), errSecSuccess)
        let storage = KeychainAccountDeletionStore(service: service)
        let fixture = DeletionFixture()
        XCTAssertThrowsError(try storage.load())
        XCTAssertThrowsError(try storage.save(fixture.record()))
        XCTAssertThrowsError(try storage.clear(ticket: fixture.ticket))
        var read = query; read[kSecReturnData as String] = true
        var value: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(read as CFDictionary, &value), errSecSuccess)
        XCTAssertEqual(value as? Data, corrupt)
    }

    func testScopeChangesRegressionSkippingAndChangedChronologyAreRejected() throws {
        let fixture = DeletionFixture()
        let initial = try fixture.record()
        var accepted = initial; try accepted.willSubmit()
        try accepted.received(fixture.receipt(), now: fixture.now)
        XCTAssertThrowsError(try accepted.validateSuccessor(of: initial))
        XCTAssertThrowsError(try initial.validateSuccessor(of: accepted))
        XCTAssertThrowsError(try DeletionFixture().record().validateSuccessor(of: initial))
        XCTAssertThrowsError(try accepted.received(fixture.receipt(requestedAt: fixture.now.addingTimeInterval(1)), now: fixture.now))
        var finished = accepted
        try finished.received(fixture.receipt(completed: true), now: fixture.now)
        XCTAssertThrowsError(try finished.finishedLocalCleanup())
        try finished.finishedProviderDisconnect()
        try finished.finishedLocalCleanup()
        XCTAssertThrowsError(try finished.validateSuccessor(of: accepted))
        XCTAssertThrowsError(try finished.received(fixture.receipt(), now: fixture.now))
    }

    func testRandomTicketAndRecordContainNoSessionCredentialsAndRedactDiagnostics() throws {
        let fixture = DeletionFixture()
        let first = try AccountDeletionTicket.random()
        let second = try AccountDeletionTicket.random()
        XCTAssertEqual(first.statusToken.count, 43)
        XCTAssertNotEqual(first, second)
        try first.validate(); try second.validate()
        let record = try fixture.record()
        let data = try JSONEncoder().encode(record)
        let encoded = String(decoding: data, as: UTF8.self)
        for secret in [fixture.session.accessToken, fixture.session.refreshToken!, "idToken", "authorizationCode", "mnemonic"] {
            XCTAssertFalse(encoded.contains(secret))
        }
        for text in [String(describing: record), String(reflecting: record)] {
            XCTAssertFalse(text.contains(record.ticket.statusToken))
            XCTAssertFalse(text.contains(record.googleUserID!))
            XCTAssertFalse(text.contains(record.walletAddress!))
        }
    }

    private func keychainQuery(_ service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service + ".account-deletion.v1",
         kSecAttrAccount as String: "request", kSecAttrSynchronizable as String: false]
    }
}
