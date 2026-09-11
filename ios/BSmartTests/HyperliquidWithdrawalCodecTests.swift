import XCTest
import WalletCore
@testable import BSmart

final class HyperliquidWithdrawalCodecTests: XCTestCase {
    func testIndependentPythonVectorsMatchTypedDigestSignatureAndWire() throws {
        for vector in try vectors() {
            let intent = try make(vector)
            XCTAssertEqual(FundingHex.encode(try HyperliquidWithdrawalCodec.signingDigest(intent)), vector.digest)
            let json = try HyperliquidWithdrawalCodec.typedJSON(intent)
            let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0, count: 31) + Data([1])))
            let signed = EthereumMessageSigner.signTypedMessage(privateKey: key, messageJson: json)
            XCTAssertEqual(signed.hasPrefix("0x") ? signed : "0x" + signed, vector.signature)
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: HyperliquidWithdrawalCodec.envelope(intent, signature: vector.signature)) as? [String: Any])
            XCTAssertEqual(Set(payload.keys), ["action", "nonce", "signature"])
            let action = try XCTUnwrap(payload["action"] as? [String: Any])
            XCTAssertEqual(action["type"] as? String, "sendToEvmWithData")
            XCTAssertEqual(action["token"] as? String, "USDC")
            XCTAssertEqual(action["amount"] as? String, vector.action.amount)
            XCTAssertEqual(action["sourceDex"] as? String, vector.action.sourceDex)
            XCTAssertEqual(action["destinationRecipient"] as? String, vector.action.destinationRecipient)
            XCTAssertEqual(action["signatureChainId"] as? String, "0xa4b1")
            XCTAssertEqual(action["hyperliquidChain"] as? String, "Mainnet")
            XCTAssertEqual(action["destinationChainId"] as? Int, 3)
            XCTAssertEqual(action["gasLimit"] as? Int, 200000)
            XCTAssertEqual(action["data"] as? String, "0x")
            XCTAssertEqual(action["nonce"] as? UInt64, vector.action.nonce)
            XCTAssertNil(payload["expiresAfter"]); XCTAssertNil(payload["builder"])
        }
    }

    func testChangedRecipientAmountSourceOrNonceCannotReuseSignature() throws {
        let vector = try XCTUnwrap(vectors().first)
        let original = try make(vector)
        for changed in [
            try make(vector, amount: "10.000001"), try make(vector, source: .perps),
            try make(vector, recipient: vector.owner), try make(vector, nonce: vector.action.nonce + 1)
        ] {
            XCTAssertNotEqual(try HyperliquidWithdrawalCodec.signingDigest(changed), try HyperliquidWithdrawalCodec.signingDigest(original))
            XCTAssertThrowsError(try HyperliquidWithdrawalCodec.envelope(changed, signature: vector.signature))
        }
    }

    func testInvalidRecipientsPrecisionFundsAndNonceFailBeforeEncoding() throws {
        let vector = try XCTUnwrap(vectors().first)
        for amount in ["0", "-1", "+1", "1e2", "1.0000001", "184467440737.095517", "01", "1.", " 1"] {
            XCTAssertThrowsError(try make(vector, amount: amount), amount)
        }
        for recipient in ["0x" + String(repeating: "0", count: 40), "0x1234", "nvda.eth", vector.owner + " ",
                          CCTPArbitrumRoute.coreDepositWallet, CCTPArbitrumRoute.coreTokenSystemAddress,
                          ArbitrumDepositPolicy.nativeUSDC, CCTPArbitrumRoute.destinationUSDC] {
            XCTAssertThrowsError(try make(vector, recipient: recipient), recipient)
        }
        XCTAssertThrowsError(try make(vector, nonce: 0))
        XCTAssertThrowsError(try make(vector, nonce: 9_007_199_254_740_992))
        XCTAssertNil(HyperliquidWithdrawalIntent.Source(rawValue: "xyz"))
        let unbacked = DeviceWalletSummary(accountID: UUID(), address: vector.owner, recoveryVerified: false)
        XCTAssertNoThrow(try HyperliquidWithdrawalIntent(wallet: unbacked, recipient: vector.action.destinationRecipient,
            amount: "10", source: .spot, nonce: vector.action.nonce))
        XCTAssertFalse(unbacked.recoveryVerified)
    }

    func testChecksumAndAmountNormalizationKeepSignatureStable() throws {
        let vector = try XCTUnwrap(vectors().first)
        let checksum = try WalletReceiveAddress(owner: vector.action.destinationRecipient).value
        let normalized = try make(vector, amount: "10.000000", recipient: checksum)
        XCTAssertEqual(normalized.amountUnits, FundingQuantity(10_000_000))
        XCTAssertEqual(try HyperliquidWithdrawalCodec.signingDigest(normalized), try HyperliquidWithdrawalCodec.signingDigest(make(vector)))
        let bad = checksum.replacingOccurrences(of: "F", with: "f")
        XCTAssertNotEqual(bad, checksum)
        XCTAssertThrowsError(try make(vector, recipient: bad))
    }

    func testHighSInvalidRecoveryIDAndWrongOwnerSignaturesAreRejected() throws {
        let vector = try XCTUnwrap(vectors().first), intent = try make(vector)
        for signature in ["0x", vector.signature + "00", String(vector.signature.dropLast(2)) + "00",
                          "0x" + String(vector.signature.dropFirst(2).prefix(64)) + String(repeating: "f", count: 64) + "1b"] {
            XCTAssertThrowsError(try HyperliquidWithdrawalCodec.envelope(intent, signature: signature))
        }
        let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0, count: 31) + Data([2])))
        let signed = EthereumMessageSigner.signTypedMessage(privateKey: key, messageJson: try HyperliquidWithdrawalCodec.typedJSON(intent))
        XCTAssertThrowsError(try HyperliquidWithdrawalCodec.envelope(intent, signature: signed.hasPrefix("0x") ? signed : "0x" + signed))
    }

    private func make(_ vector: Vector, amount: String? = nil, source: HyperliquidWithdrawalIntent.Source? = nil,
                      recipient: String? = nil, nonce: UInt64? = nil) throws -> HyperliquidWithdrawalIntent {
        try .init(wallet: .init(accountID: UUID(), address: vector.owner, recoveryVerified: true),
            recipient: recipient ?? vector.action.destinationRecipient, amount: amount ?? vector.action.amount,
            source: source ?? XCTUnwrap(.init(rawValue: vector.action.sourceDex)), nonce: nonce ?? vector.action.nonce)
    }

    private func vectors() throws -> [Vector] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "hyperliquid-withdrawal-vectors", withExtension: "json"))
        struct Root: Decodable { let vectors: [Vector] }
        return try JSONDecoder().decode(Root.self, from: Data(contentsOf: url)).vectors
    }

    private struct Vector: Decodable {
        let owner: String, digest: String, signature: String
        let action: Action
        struct Action: Decodable { let amount: String, sourceDex: String, destinationRecipient: String; let nonce: UInt64 }
    }
}
