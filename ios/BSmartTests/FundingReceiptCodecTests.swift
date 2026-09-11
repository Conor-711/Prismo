import XCTest
@testable import BSmart

final class FundingReceiptCodecTests: XCTestCase {
    func testIndependentABIMessageAndEveryByteAreValidated() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let fixture = try await fixture(context)
        let vector = try FundingObservationFixture.vector()
        XCTAssertEqual(CCTPSourceMessage.topic, vector["topic"])
        let bytes = try XCTUnwrap(FundingHex.decode(vector["event"]!))
        let message = try CCTPSourceMessage.decodeEvent(bytes, intent: fixture.record.intent)
        XCTAssertEqual(message.count, 432)
        for index in bytes.indices {
            var altered = bytes; altered[index] ^= 1
            XCTAssertThrowsError(try CCTPSourceMessage.decodeEvent(altered, intent: fixture.record.intent), "Byte \(index)")
        }
        for invalid in [Data(), Data(bytes.dropLast()), bytes + Data([0])] {
            XCTAssertThrowsError(try CCTPSourceMessage.decodeEvent(invalid, intent: fixture.record.intent))
        }
    }

    func testExactTransactionAndReceiptIncludingActualGasFee() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let f = try await fixture(context)
        let location = try FundingReceiptCodec.transaction(f.transaction(), record: f.record)
        let receipt = try FundingReceiptCodec.receipt(f.receipt(), record: f.record)
        XCTAssertEqual(receipt.location, location)
        XCTAssertEqual(receipt.messageLogIndex, 5)
        XCTAssertEqual(try receipt.networkFee.formatted(decimals: 18), "0.000002")
        XCTAssertNil(try FundingReceiptCodec.transaction(f.transaction(pending: true), record: f.record))
        let reverted = try FundingReceiptCodec.receipt(f.receipt(reverted: true), record: f.record)
        XCTAssertFalse(reverted.succeeded)
        XCTAssertNil(reverted.message)
    }

    func testTransactionCannotChangeAnySignedFieldOrAcceptWrongLocation() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let f = try await fixture(context)
        let transaction = try f.transaction()
        let edits: [String: FundingRPCValue] = ["hash": .string(FundingQuantity(3).abi), "from": .string(CCTPArbitrumRoute.forwarderAddress),
            "to": .string(CCTPArbitrumRoute.tokenMessenger), "chainId": .string("0x1"), "type": .string("0x4"),
            "value": .string("0x1"), "nonce": .string("0x1"), "gas": .string("0x1"), "maxFeePerGas": .string("0x1"),
            "maxPriorityFeePerGas": .string("0x1"), "input": .string("0x"), "accessList": .array([.object([:])]),
            "authorizationList": .array([]), "r": .string("0x0"), "s": .string("0x0"), "v": .string("0x1b"),
            "yParity": .string("0x2"), "blockHash": .string(FundingQuantity(0).abi), "blockNumber": .string("0x0"),
            "transactionIndex": .string("0x01")]
        for (key, value) in edits {
            XCTAssertThrowsError(try FundingReceiptCodec.transaction(replacing(transaction, key, with: value), record: f.record), key)
        }
        XCTAssertThrowsError(try FundingReceiptCodec.transaction(replacing(transaction, "blockHash", with: .null), record: f.record))
    }

    func testReceiptRejectsInvalidStatusGasAndUnrelatedOrTamperedLogs() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let f = try await fixture(context)
        let receipt = try f.receipt()
        let log = try f.log()
        let receiptEdits: [String: FundingRPCValue] = ["transactionHash": .string(FundingQuantity(2).abi),
            "from": .string(CCTPArbitrumRoute.forwarderAddress), "to": .string(CCTPArbitrumRoute.tokenMessenger),
            "type": .string("0x0"), "contractAddress": .string(f.record.intent.owner), "status": .string("0x2"),
            "gasUsed": .string("0x30d400"), "effectiveGasPrice": .string("0x9896800"),
            "logs": .array([])]
        for (key, value) in receiptEdits {
            XCTAssertThrowsError(try FundingReceiptCodec.receipt(replacing(receipt, key, with: value), record: f.record), key)
        }
        let logEdits: [String: FundingRPCValue] = ["removed": .bool(true), "transactionHash": .string(FundingQuantity(4).abi),
            "blockNumber": .string("0x97"), "blockHash": .string(FundingQuantity(151).abi), "transactionIndex": .string("0x3"),
            "address": .string(CCTPArbitrumRoute.tokenMessenger), "topics": .array([.string(FundingQuantity(4).abi)]),
            "data": .string("0x00"), "logIndex": .string("0x01")]
        for (key, value) in logEdits {
            let altered = try replacing(log, key, with: value)
            XCTAssertThrowsError(try FundingReceiptCodec.receipt(replacing(receipt, "logs", with: .array([altered])), record: f.record), key)
        }
        for logs in [[log, log], [log, try replacing(log, "logIndex", with: .string("0x6"))], Array(repeating: log, count: 25)] {
            XCTAssertThrowsError(try FundingReceiptCodec.receipt(replacing(receipt, "logs", with: .array(logs)), record: f.record))
        }
        XCTAssertThrowsError(try FundingReceiptCodec.receipt(replacing(receipt, "status", with: .string("0x0")), record: f.record))
    }

    private func fixture(_ context: FundingJournalTestContext) async throws -> FundingObservationFixture {
        let journal = try context.journal(); let id = UUID()
        _ = try await context.ready(context.transaction(), id: id, journal: journal)
        let lookup = try await journal.sourceLookup(id: id, wallet: context.wallet)
        return .init(record: lookup.record, now: context.clock.now.addingTimeInterval(120))
    }
}
