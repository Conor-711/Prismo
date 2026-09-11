import XCTest
@testable import BSmart

final class CCTPForwardReceiptTests: XCTestCase {
    func testIndependentPerpsFeeAndSpotVectorsUseExactEightDecimals() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (_, lookup) = try await context.forwardingReady()
        let proof = try XCTUnwrap(lookup.attestation.proof)
        let fixture = try ForwardVector.load()
        for mode in ["perps", "fee", "spot"] {
            let receipt = try CCTPForwardReceipt.decode(fixture.receipt(mode), hash: fixture.hash, proof: proof, intent: lookup.record.intent)
            let result = try receipt.resolution(proof: proof, intent: lookup.record.intent)
            XCTAssertEqual(result.destinationDex, mode == "spot" ? UInt32.max : 0)
            XCTAssertEqual(result.coreAmount.formatted(decimals: 8), mode == "fee" ? "8.79999999" : "9.8")
            XCTAssertEqual(result.accountFee, FundingQuantity(mode == "fee" ? 100_000_001 : 0))
            XCTAssertEqual(receipt.location.blockNumber, 490)
        }
        XCTAssertThrowsError(try FundingQuantity(0).subtracting(FundingQuantity(1)))
        XCTAssertEqual(try FundingQuantity(1).subtracting(FundingQuantity(1)), FundingQuantity(0))
    }

    func testEveryEventTopicAddressDataByteAndLocationAreBound() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (_, lookup) = try await context.forwardingReady()
        let fixture = try ForwardVector.load(); let proof = try XCTUnwrap(lookup.attestation.proof)
        let original = try FundingReceiptCodec.fields(fixture.receipt("fee"))
        guard case .array(let logs) = original["logs"] else { return XCTFail("Missing logs") }
        for index in logs.indices {
            let fields = try FundingReceiptCodec.fields(logs[index])
            for (key, value): (String, FundingRPCValue) in [
                ("address", .string(context.wallet.address)), ("removed", .bool(true)), ("blockNumber", .string("0x1")),
                ("blockHash", .string(FundingQuantity(999).abi)), ("transactionIndex", .string("0x3")),
                ("transactionHash", .string(FundingQuantity(999).abi)), ("logIndex", .string("0x0"))
            ] {
                var changed = fields; changed[key] = value
                var altered = logs; altered[index] = .object(changed)
                var receipt = original; receipt["logs"] = .array(altered)
                // The first log's arbitrary index is valid; it is ordering/identity, not a predefined constant.
                if index == 0 && key == "logIndex" { continue }
                XCTAssertThrowsError(try CCTPForwardReceipt.decode(.object(receipt), hash: fixture.hash, proof: proof, intent: lookup.record.intent), "\(index) \(key)")
            }
            guard case .array(let topics) = fields["topics"] else { return XCTFail("Missing topics") }
            for topic in topics.indices {
                var changed = fields; var alteredTopics = topics; alteredTopics[topic] = .string(FundingQuantity(999).abi)
                changed["topics"] = .array(alteredTopics)
                var altered = logs; altered[index] = .object(changed); var receipt = original; receipt["logs"] = .array(altered)
                XCTAssertThrowsError(try CCTPForwardReceipt.decode(.object(receipt), hash: fixture.hash, proof: proof, intent: lookup.record.intent))
            }
            let data = try XCTUnwrap(FundingHex.decode(FundingReceiptCodec.text(fields, "data")))
            for offset in data.indices {
                var changedData = data; changedData[offset] ^= 1
                var changed = fields; changed["data"] = .string(FundingHex.encode(changedData))
                var altered = logs; altered[index] = .object(changed); var receipt = original; receipt["logs"] = .array(altered)
                XCTAssertThrowsError(try CCTPForwardReceipt.decode(.object(receipt), hash: fixture.hash, proof: proof, intent: lookup.record.intent), "\(index) byte \(offset)")
            }
        }
    }

    func testMissingRepeatedInterleavedAndOversizedLogsCannotMixTwoMessages() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (_, lookup) = try await context.forwardingReady()
        let fixture = try ForwardVector.load(); let proof = try XCTUnwrap(lookup.attestation.proof)
        let original = try FundingReceiptCodec.fields(fixture.receipt())
        guard case .array(let logs) = original["logs"] else { return XCTFail("Missing logs") }
        for index in logs.indices {
            var missing = logs; missing.remove(at: index)
            var duplicate = logs; duplicate.insert(logs[index], at: index)
            for altered in [missing, duplicate] {
                var receipt = original; receipt["logs"] = .array(altered)
                XCTAssertThrowsError(try CCTPForwardReceipt.decode(.object(receipt), hash: fixture.hash, proof: proof, intent: lookup.record.intent))
            }
        }
        for (key, value): (String, FundingRPCValue) in [
            ("status", .string("0x0")), ("status", .string("0x2")), ("contractAddress", .string(context.wallet.address)),
            ("logs", .array(Array(repeating: logs[0], count: 129))), ("transactionHash", .string(FundingQuantity(99).abi))
        ] {
            var receipt = original; receipt[key] = value
            XCTAssertThrowsError(try CCTPForwardReceipt.decode(.object(receipt), hash: fixture.hash, proof: proof, intent: lookup.record.intent))
        }
        var other = try FundingReceiptCodec.fields(logs[0]); other["logIndex"] = .string("0xb")
        guard case .array(var topics) = other["topics"] else { return XCTFail("Missing topics") }
        topics[2] = .string(FundingQuantity(99).abi); other["topics"] = .array(topics)
        var interleaved = logs; interleaved.insert(.object(other), at: 1)
        var receipt = original; receipt["logs"] = .array(interleaved)
        XCTAssertThrowsError(try CCTPForwardReceipt.decode(.object(receipt), hash: fixture.hash, proof: proof, intent: lookup.record.intent))
        // An earlier different message is allowed in a relayer batch, but cannot supply this message's events.
        other["logIndex"] = .string("0x1"); receipt["logs"] = .array([.object(other)] + logs)
        XCTAssertNoThrow(try CCTPForwardReceipt.decode(.object(receipt), hash: fixture.hash, proof: proof, intent: lookup.record.intent))
    }
}
