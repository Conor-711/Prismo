import XCTest
@testable import BSmart

final class DeviceWalletCryptographyTests: XCTestCase {
    // Public BIP39 zero-entropy vector. Never use this wallet for funds.
    private let zeroEntropy = Data(repeating: 0, count: 32)
    private let expectedAddress = "0xf278cf59f82edcf871d630f28ecc8056f25c1cdb"

    func testStandardRecoveryDerivesTheSameAddressIndependentlyOfAccountIdentity() throws {
        let words = try DeviceWalletCryptography.recoveryWords(entropy: zeroEntropy)
        XCTAssertEqual(words, Array(repeating: "abandon", count: 23) + ["art"])
        XCTAssertEqual(try DeviceWalletCryptography.entropy(phrase: words.joined(separator: " ")), zeroEntropy)
        XCTAssertEqual(try DeviceWalletCryptography.address(entropy: zeroEntropy), expectedAddress)
    }

    func testEntropyIsIndependentAndExactly256Bits() throws {
        let a = try DeviceWalletCryptography.generateEntropy()
        let b = try DeviceWalletCryptography.generateEntropy()
        XCTAssertEqual(a.count, 32)
        XCTAssertEqual(b.count, 32)
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(try DeviceWalletCryptography.address(entropy: a), try DeviceWalletCryptography.address(entropy: b))
    }

    func testRejectsBadChecksumLengthCharactersAndEntropy() throws {
        for phrase in [Array(repeating: "abandon", count: 24).joined(separator: " "),
                       Array(repeating: "abandon", count: 12).joined(separator: " "),
                       Array(repeating: "abandon", count: 23).joined(separator: " ") + " caf\u{00e9}",
                       String(repeating: "x", count: 513)] {
            XCTAssertThrowsError(try DeviceWalletCryptography.entropy(phrase: phrase))
        }
        XCTAssertThrowsError(try DeviceWalletCryptography.address(entropy: Data(repeating: 0, count: 16)))
    }

    func testCanonicalMessageAndSignatureMatchPythonEthereumImplementation() throws {
        let issued = ISO8601DateFormatter().date(from: "2026-09-10T00:00:00Z")!
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let challenge = TradingWalletChallenge(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                                              accountId: accountID, address: expectedAddress,
                                              nonce: String(repeating: "a", count: 64), issuedAt: issued,
                                              expiresAt: issued.addingTimeInterval(300))
        let message = try challenge.message(accountID: accountID, address: expectedAddress, now: issued)
        XCTAssertTrue(message.contains("Chain ID: 42161\nChallenge: 00000000-0000-0000-0000-000000000002"))
        XCTAssertTrue(message.contains("Issued At: 2026-09-10T00:00:00Z\nExpires At: 2026-09-10T00:05:00Z"))
        let signature = try DeviceWalletCryptography.bindingSignature(entropy: zeroEntropy, challenge: challenge,
                                                                      accountID: accountID, now: issued)
        XCTAssertEqual(signature, "0x219475024e82689a618eb2bfd96d6c1cbc4118665f16130d6530301be46be8261bc248cb708cd88fd86082a27f94d12af0aa3e48e249b53d4a322b02f11e31301b")
        XCTAssertThrowsError(try challenge.message(accountID: UUID(), address: expectedAddress, now: issued))
        XCTAssertThrowsError(try challenge.message(accountID: accountID, address: "0x" + String(repeating: "1", count: 40), now: issued))
        XCTAssertThrowsError(try challenge.message(accountID: accountID, address: expectedAddress, now: issued.addingTimeInterval(301)))
    }

    func testRecordCannotBeReassignedOrSilentlyMigrated() throws {
        let account = UUID()
        let record = DeviceWalletRecord(version: 1, accountID: account, address: expectedAddress,
                                       entropy: zeroEntropy, recoveryVerified: false)
        XCTAssertFalse(try record.validated(accountID: account).recoveryVerified)
        XCTAssertThrowsError(try record.validated(accountID: UUID()))
        let badVersion = DeviceWalletRecord(version: 2, accountID: account, address: expectedAddress,
                                           entropy: zeroEntropy, recoveryVerified: true)
        XCTAssertThrowsError(try badVersion.validated(accountID: account))
        let badAddress = DeviceWalletRecord(version: 1, accountID: account, address: "0x" + String(repeating: "1", count: 40),
                                           entropy: zeroEntropy, recoveryVerified: true)
        XCTAssertThrowsError(try badAddress.validated(accountID: account))
    }

    func testRegistrationMustExplicitlySayUnboundNotJustOmitAddress() throws {
        let account = UUID().uuidString
        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode(TradingWalletRegistration.self, from: Data("{\"accountId\":\"\(account)\"}".utf8)))
        XCTAssertThrowsError(try decoder.decode(TradingWalletRegistration.self,
            from: Data("{\"accountId\":\"\(account)\",\"address\":\"0x0000000000000000000000000000000000000000\"}".utf8)))
        let unbound = try decoder.decode(TradingWalletRegistration.self,
            from: Data("{\"accountId\":\"\(account)\",\"address\":null}".utf8))
        XCTAssertNil(unbound.address)
    }
}
