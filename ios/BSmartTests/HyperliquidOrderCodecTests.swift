import XCTest
import WalletCore
@testable import BSmart

final class HyperliquidOrderCodecTests: XCTestCase {
    func testOfficialSDKVectorsMatchBytesHashTypedDigestSignatureAndJSON() throws {
        for vector in try vectors() {
            let order = try makeOrder(vector)
            XCTAssertEqual(FundingHex.encode(try HyperliquidOrderCodec.messagePack(order)), vector.messagePack, vector.name)
            XCTAssertEqual(FundingHex.encode(try HyperliquidOrderCodec.actionHash(order)), vector.actionHash, vector.name)
            XCTAssertEqual(FundingHex.encode(try HyperliquidOrderCodec.signingDigest(order)), vector.digest, vector.name)
            let json = try HyperliquidOrderCodec.typedJSON(order)
            // Public disposable key 1, not a device key or funded account.
            let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0, count: 31) + Data([1])))
            let signature = EthereumMessageSigner.signTypedMessage(privateKey: key, messageJson: json)
            XCTAssertEqual(signature.hasPrefix("0x") ? signature : "0x" + signature, vector.signature, vector.name)
            let actual = try XCTUnwrap(JSONSerialization.jsonObject(with:
                HyperliquidOrderCodec.envelope(order, signature: vector.signature)) as? [String: Any])
            let expected = try rawVector(named: vector.name)
            XCTAssertEqual(actual["action"] as? NSDictionary, expected["action"] as? NSDictionary)
            let typed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary
            XCTAssertEqual(typed, expected["typedData"] as? NSDictionary)
            XCTAssertEqual((actual["nonce"] as? NSNumber)?.uint64Value, vector.nonce)
            XCTAssertEqual((actual["expiresAfter"] as? NSNumber)?.uint64Value, vector.expiresAfter)
            XCTAssertEqual(Set(actual.keys), ["action", "nonce", "expiresAfter", "signature"])
            let parts = try XCTUnwrap(actual["signature"] as? [String: Any])
            XCTAssertEqual(parts["r"] as? String, "0x" + String(vector.signature.dropFirst(2).prefix(64)))
            XCTAssertEqual(parts["s"] as? String, "0x" + String(vector.signature.dropFirst(66).prefix(64)))
            XCTAssertEqual(parts["v"] as? Int, Int(vector.signature.suffix(2), radix: 16))
        }
    }

    func testSemanticChangesCannotReuseSignature() throws {
        let vector = try XCTUnwrap(try vectors().first { $0.name == "builder" })
        let order = try makeOrder(vector)
        XCTAssertNoThrow(try HyperliquidOrderCodec.envelope(order, signature: vector.signature))
        let variants = [
            try HyperliquidOrderTestSupport.order(side: .sell),
            try HyperliquidOrderTestSupport.order(size: "3.126"),
            try HyperliquidOrderTestSupport.order(price: "230.8"),
            try HyperliquidOrderTestSupport.order(reduceOnly: true),
            try HyperliquidOrderTestSupport.order(cloid: "0x00000000000000000000000000000003"),
            try HyperliquidOrderTestSupport.order(nonce: vector.nonce + 1),
            try HyperliquidOrderTestSupport.order(expiresAfter: vector.expiresAfter + 1)
        ]
        for changed in variants {
            XCTAssertThrowsError(try HyperliquidOrderCodec.envelope(changed, signature: vector.signature))
            XCTAssertNotEqual(try HyperliquidOrderCodec.actionHash(changed), try HyperliquidOrderCodec.actionHash(order))
        }
    }

    func testMalformedHighSAndDifferentOwnerSignaturesRejected() throws {
        let vector = try XCTUnwrap(try vectors().first)
        let order = try makeOrder(vector)
        let r = String(vector.signature.dropFirst(2).prefix(64))
        for signature in ["0x", vector.signature + "00", vector.signature.uppercased(),
                          String(vector.signature.dropLast(2)) + "00", "0x" + r + String(repeating: "f", count: 64) + "1b",
                          "0x" + String(repeating: "0", count: 128) + "1b"] {
            XCTAssertThrowsError(try HyperliquidOrderCodec.envelope(order, signature: signature))
        }
        let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0, count: 31) + Data([2])))
        let signature = EthereumMessageSigner.signTypedMessage(privateKey: key,
            messageJson: try HyperliquidOrderCodec.typedJSON(order))
        XCTAssertThrowsError(try HyperliquidOrderCodec.envelope(order,
            signature: signature.hasPrefix("0x") ? signature : "0x" + signature))
    }

    func testDeterministicEncodingAcrossRepeatedCalls() throws {
        let order = try HyperliquidOrderTestSupport.order()
        let bytes = try HyperliquidOrderCodec.messagePack(order)
        for _ in 0..<100 { XCTAssertEqual(try HyperliquidOrderCodec.messagePack(order), bytes) }
    }

    func testBuilderRecipientAndFeeAreBoundIntoSignature() throws {
        let vector = try XCTUnwrap(try vectors().first { $0.name == "builder-code" })
        let original = try makeOrder(vector)
        let fee = try XCTUnwrap(original.builderFee)
        let changes: [HyperliquidBuilderFee?] = [nil,
            try .init(address: fee.address, tenthsOfBasisPoint: 11),
            try .init(address: HyperliquidOrderTestSupport.wallet.address, tenthsOfBasisPoint: 10)]
        for changed in changes {
            let order = try HyperliquidOrderIntent(wallet: HyperliquidOrderTestSupport.wallet, market: original.market,
                side: original.side, size: original.size.wire, limitPrice: original.limitPrice.wire,
                reduceOnly: original.reduceOnly, cloid: original.cloid, nonce: original.nonce,
                expiresAfter: original.expiresAfter, builderFee: changed)
            XCTAssertNotEqual(try HyperliquidOrderCodec.actionHash(order), try HyperliquidOrderCodec.actionHash(original))
            XCTAssertThrowsError(try HyperliquidOrderCodec.envelope(order, signature: vector.signature))
        }
    }

    private func makeOrder(_ vector: Vector) throws -> HyperliquidOrderIntent {
        try .init(wallet: HyperliquidOrderTestSupport.wallet,
            market: HyperliquidOrderTestSupport.market(asset: vector.asset, decimals: vector.sizeDecimals),
            side: vector.isBuy ? .buy : .sell, size: vector.inputSize, limitPrice: vector.inputPrice,
            reduceOnly: vector.reduceOnly, cloid: vector.cloid, nonce: vector.nonce, expiresAfter: vector.expiresAfter,
            builderFee: vector.action.builder.map { try .init(address: $0.b, tenthsOfBasisPoint: $0.f) })
    }

    private func data() throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: "hyperliquid-order-vectors", withExtension: "json")))
    }
    private func vectors() throws -> [Vector] {
        struct Fixture: Decodable { let vectors: [Vector] }
        return try JSONDecoder().decode(Fixture.self, from: data()).vectors
    }
    private func rawVector(named name: String) throws -> [String: Any] {
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data()) as? [String: Any])
        return try XCTUnwrap((root["vectors"] as? [[String: Any]])?.first { $0["name"] as? String == name })
    }
    private struct Vector: Decodable {
        struct Action: Decodable {
            struct Builder: Decodable { let b: String; let f: UInt16 }
            let builder: Builder?
        }
        let action: Action
        let name: String
        let asset: UInt32
        let sizeDecimals: Int
        let inputSize, inputPrice, cloid: String
        let isBuy, reduceOnly: Bool
        let nonce, expiresAfter: UInt64
        let messagePack, actionHash, digest, signature: String
    }
}
