import XCTest
import Security
@testable import BSmart

final class FundingJournalIntegrityTests: XCTestCase {
    func testAuthenticatedRecordBindsTheKeyLedgerSequenceAndContents() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let transaction = try await context.transaction()
        let record = FundingJournalRecord(intent: .init(id: UUID(), transaction: transaction), state: .prepared,
                                           signed: nil, updatedAt: context.clock.now)
        let anchor = FundingJournalAnchor.create()
        let (sealed, checkpoint) = try FundingJournalCryptography.seal(record, anchor: anchor)
        XCTAssertEqual(try FundingJournalCryptography.open(sealed, checkpoint: checkpoint, anchor: anchor), record)
        let wrongKey = FundingJournalAnchor(version: 1, id: anchor.id, key: Data(repeating: 1, count: 32),
                                             committed: .empty, pending: nil)
        XCTAssertThrowsError(try FundingJournalCryptography.open(sealed, checkpoint: checkpoint, anchor: wrongKey))
        XCTAssertThrowsError(try FundingJournalCryptography.open(sealed, checkpoint: checkpoint, anchor: .create()))
        let wrongSequence = FundingJournalCheckpoint(sequence: 2, digest: checkpoint.digest)
        XCTAssertThrowsError(try FundingJournalCryptography.open(sealed, checkpoint: wrongSequence, anchor: anchor))
        var changed = sealed
        changed[changed.count - 1] ^= 1
        XCTAssertThrowsError(try FundingJournalCryptography.open(changed, checkpoint: checkpoint, anchor: anchor))
    }

    func testHistoricalMetadataCannotContradictItsAuthorizationOrTransaction() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let transaction = try await context.transaction()
        let intent = FundingJournalIntent(id: UUID(), transaction: transaction)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(intent)) as? [String: Any])
        let changes: [(String, Any)] = [
            ("amountUnits", 11_000_000), ("maximumCCTPFeeUnits", 239_999), ("protocolRateMillionths", 1),
            ("forwardingFeeUnits", 200_001), ("chainID", 1), ("nonce", "0x1"),
            ("owner", "0x" + String(repeating: "1", count: 40)),
            ("authorizationNonce", "0x" + String(repeating: "2", count: 64)),
            ("authorization", "0x" + String(repeating: "0", count: 130))
        ]
        for (field, value) in changes {
            var modified = original
            modified[field] = value
            let decoded = try JSONDecoder().decode(FundingJournalIntent.self, from: JSONSerialization.data(withJSONObject: modified))
            let record = FundingJournalRecord(intent: decoded, state: .prepared, signed: nil, updatedAt: context.clock.now)
            XCTAssertThrowsError(try record.validate(after: nil), field)
        }
    }

    func testSignedHistoryCannotSwapSignatureRawBytesOrHash() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let transaction = try await context.transaction()
        let signed = try context.signed(transaction)
        let intent = FundingJournalIntent(id: UUID(), transaction: transaction)
        let previous = FundingJournalRecord(intent: intent, state: .signing, signed: nil, updatedAt: context.clock.now)
        var changedRaw = signed.raw
        changedRaw[changedRaw.count - 1] ^= 1
        for value in [
            FundingJournalRecord.Signed(signature: signed.signature, raw: changedRaw, hash: signed.hash),
            .init(signature: Data(count: 65), raw: signed.raw, hash: signed.hash),
            .init(signature: signed.signature, raw: signed.raw, hash: "0x" + String(repeating: "f", count: 64))
        ] {
            let record = FundingJournalRecord(intent: intent, state: .signed, signed: value, updatedAt: context.clock.now)
            XCTAssertThrowsError(try record.validate(after: previous))
        }
    }

    func testCorruptKeychainAnchorIsNotReplaced() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        _ = try await journal.records(wallet: context.wallet)
        let damaged = Data("not a journal anchor".utf8)
        _ = context.keychain.update([:], values: [kSecValueData as String: damaged])
        await expectJournalFailure { try await journal.records(wallet: context.wallet) }
        XCTAssertEqual(context.keychain.data, damaged)
    }
}
