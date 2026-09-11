import XCTest
import WalletCore
@testable import BSmart

final class CCTPAttestedMessageTests: XCTestCase {
    func testIndependentVectorAndAllImmutableMessageBytes() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (_, lookup) = try await context.attestationReady()
        let vector = try AttestationVector.load()
        let proof = try vector.proof()
        let source = try XCTUnwrap(lookup.source.receipt?.message)
        XCTAssertEqual(FundingHex.encode(Hash.keccak256(data: proof.message)), vector.digest)
        XCTAssertEqual(try proof.signers(), vector.signers)
        XCTAssertEqual(try proof.fee, FundingQuantity(200_000))
        XCTAssertEqual(try proof.expiration, 1000)
        try proof.validate(source: source, intent: lookup.record.intent)
        for index in 0..<432 where ![12..<44, 144..<148, 312..<344, 344..<376].contains(where: { $0.contains(index) }) {
            var message = proof.message; message[index] ^= 1
            XCTAssertThrowsError(try CCTPAttestedMessage(message: message, attestation: proof.attestation)
                .validate(source: source, intent: lookup.record.intent), "immutable byte \(index)")
        }
    }

    func testMutableFieldsStillHaveStrictBounds() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let (_, lookup) = try await context.attestationReady()
        let proof = try AttestationVector.load().proof()
        let source = try XCTUnwrap(lookup.source.receipt?.message)
        for (range, replacement) in [
            (12..<44, Data(repeating: 0, count: 32)),
            (144..<148, Data([0, 0, 0, 0])),
            (144..<148, Data([0, 0, 3, 231])),
            (312..<344, try XCTUnwrap(FundingHex.decode(FundingQuantity(240_001).abi))),
            (344..<376, Data(repeating: 0, count: 32)),
            (344..<376, Data(repeating: 255, count: 32))
        ] {
            var message = proof.message; message.replaceSubrange(range, with: replacement)
            let changed = try AttestationVector.sign(message)
            XCTAssertThrowsError(try changed.validate(source: source, intent: lookup.record.intent))
        }
        var finalized = proof.message
        finalized.replaceSubrange(144..<148, with: Data([0, 0, 7, 208]))
        finalized.replaceSubrange(344..<376, with: Data(repeating: 0, count: 32))
        try AttestationVector.sign(finalized).validate(source: source, intent: lookup.record.intent)
    }

    func testMalformedPayloadNeverTrapsAndSignaturesAreDistinctOrderedLowS() throws {
        let proof = try AttestationVector.load().proof()
        for length in [0, 12, 43, 431, 433] {
            let malformed = CCTPAttestedMessage(message: Data(repeating: 0, count: length), attestation: proof.attestation)
            XCTAssertThrowsError(try malformed.nonce)
            XCTAssertThrowsError(try malformed.expiration)
            XCTAssertThrowsError(try malformed.signers())
        }
        var invalidV = proof.attestation; invalidV[64] = 0
        var highS = proof.attestation; highS.replaceSubrange(32..<64, with: Data(repeating: 255, count: 32))
        for signature in [Data(), Data(proof.attestation.prefix(64)),
                          Data(proof.attestation.suffix(65)) + Data(proof.attestation.prefix(65)),
                          Data(proof.attestation.prefix(65)) + Data(proof.attestation.prefix(65)), invalidV, highS,
                          Data(repeating: 0, count: 17 * 65)] {
            XCTAssertThrowsError(try CCTPAttestedMessage(message: proof.message, attestation: signature).signers())
        }
        let sliced = (Data([0]) + proof.message).dropFirst()
        XCTAssertThrowsError(try CCTPAttestedMessage(message: sliced, attestation: proof.attestation).nonce)
    }
}
