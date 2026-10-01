import XCTest
import WalletCore
@testable import BSmart

final class EquityCowOrderCodecTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_812_800)

    func testBothChainsMatchOfficialSDKTypedDataDigestUIDAndSignature() throws {
        for vector in try vectors() {
            let payload = try decode(vector), consent = review(payload), wallet = wallet(payload)
            let json = try EquityCowOrderCodec.typedJSON(payload, consent: consent, wallet: wallet, now: now)
            XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary,
                           vector["typedData"] as? NSDictionary)
            XCTAssertEqual(FundingHex.encode(EthereumAbi.encodeTyped(messageJson: json)), payload.prepared.orderDigest)
            // Disposable public test key 1 only; no real wallet is accessed.
            let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0, count: 31) + Data([1])))
            let raw = EthereumMessageSigner.signTypedMessage(privateKey: key, messageJson: json)
            let signature = raw.hasPrefix("0x") ? raw : "0x" + raw
            XCTAssertEqual(signature, vector["signature"] as? String)
            XCTAssertEqual(try EquityCowOrderCodec.verifySignature(signature, payload: payload,
                consent: consent, wallet: wallet, now: now), signature)
        }
    }

    func testOrderAndDomainSubstitutionAreRejected() throws {
        let vector = try XCTUnwrap(vectors().first)
        let payload = try decode(vector), consent = review(payload)
        for (section, key, value) in [
            ("order", "receiver", "0x" + String(repeating: "2", count: 40) as Any),
            ("order", "buyToken", "0x" + String(repeating: "2", count: 40)),
            ("order", "sellAmount", "100000001"), ("order", "buyAmount", "1"),
            ("order", "kind", "buy"), ("order", "partiallyFillable", true),
            ("order", "feeAmount", "1"), ("order", "sellTokenBalance", "internal"),
            ("order", "appData", "0x" + String(repeating: "f", count: 64)),
            ("domain", "chainId", 42161), ("domain", "name", "Exchange"),
            ("domain", "verifyingContract", "0x" + String(repeating: "2", count: 40))
        ] {
            var root = try root(vector), p = root["prepared"] as! [String: Any], child = p[section] as! [String: Any]
            child[key] = value; p[section] = child; root["prepared"] = p
            XCTAssertThrowsError(try encode(root, consent: consent, wallet: wallet(payload)))
        }
    }

    func testSigningExposureRequiredAndExecutionOrSellForbidden() throws {
        let vector = try XCTUnwrap(vectors().first), payload = try decode(vector)
        for (key, value) in [("state", "reserved" as Any), ("executionEnabled", true), ("schema", "unknown")] {
            var root = try root(vector); root[key] = value
            XCTAssertThrowsError(try encode(root, consent: review(payload), wallet: wallet(payload)))
        }
        var root = try root(vector), p = root["prepared"] as! [String: Any]
        p["side"] = "sell"; root["prepared"] = p
        XCTAssertThrowsError(try encode(root, consent: review(payload), wallet: wallet(payload)))
    }

    func testAccountIntentVersionUIDAndAssetMustMatchReviewedConsent() throws {
        let vector = try XCTUnwrap(vectors().first), payload = try decode(vector)
        let consent = review(payload)
        for (key, value) in [("intentId", UUID().uuidString as Any), ("account", UUID().uuidString),
                             ("intentVersion", 2), ("fingerprint", String(repeating: "a", count: 64)),
                             ("orderUid", "0x" + String(repeating: "0", count: 112)),
                             ("orderDigest", "0x" + String(repeating: "0", count: 64))] {
            var root = try root(vector), p = root["prepared"] as! [String: Any]
            p[key] = value; root["prepared"] = p
            XCTAssertThrowsError(try encode(root, consent: consent, wallet: wallet(payload)))
        }
        let other = DeviceWalletSummary(accountID: UUID(), address: payload.prepared.owner, recoveryVerified: true)
        XCTAssertThrowsError(try EquityCowOrderCodec.typedJSON(payload, consent: consent, wallet: other, now: now))
    }

    func testUnknownExtensionsAreRejectedAtEveryNestingLevel() throws {
        let vector = try XCTUnwrap(vectors().first)
        for section in ["root", "prepared", "instrument", "order", "domain"] {
            var root = try root(vector)
            if section == "root" { root["typedData"] = [:] }
            else {
                var p = root["prepared"] as! [String: Any]
                if section == "prepared" { p["signingScheme"] = "eth_sign" }
                else { var child = p[section] as! [String: Any]; child["hooks"] = []; p[section] = child }
                root["prepared"] = p
            }
            XCTAssertThrowsError(try EquityCowSigningPayload.decode(JSONSerialization.data(withJSONObject: root)))
        }
        XCTAssertThrowsError(try EquityCowSigningPayload.decode(Data(repeating: 32, count: 16_385)))
    }

    func testCanonicalPositiveUint256NeverUsesFloatingPointOrUInt64() throws {
        let vector = try XCTUnwrap(vectors().first)
        for amount in ["0", "01", "1e18", "1.5", "-1", String(repeating: "9", count: 78)] {
            var root = try root(vector), p = root["prepared"] as! [String: Any], order = p["order"] as! [String: Any]
            order["sellAmount"] = amount; p["order"] = order; root["prepared"] = p
            let altered = try EquityCowSigningPayload.decode(JSONSerialization.data(withJSONObject: root))
            XCTAssertThrowsError(try EquityCowOrderCodec.typedJSON(altered, consent: review(altered), wallet: wallet(altered), now: now))
        }
        // Additional official SDK vector exceeds UInt64's capacity.
        let payload = try decode(XCTUnwrap(vectors().last))
        XCTAssertNil(UInt64(payload.prepared.order.buyAmount))
        XCTAssertNoThrow(try EquityCowOrderCodec.typedJSON(payload, consent: review(payload), wallet: wallet(payload), now: now))
    }

    func testClockRollbackStaleSigningAndExpiryFailClosed() throws {
        let payload = try decode(XCTUnwrap(vectors().first))
        for seconds in [-1.0, 30, 55, 600] {
            XCTAssertThrowsError(try EquityCowOrderCodec.typedJSON(payload, consent: review(payload), wallet: wallet(payload),
                now: now.addingTimeInterval(seconds)))
        }
    }

    func testInvalidSignatureWrongOwnerHighSAndEthSignAreRejected() throws {
        let vector = try XCTUnwrap(vectors().first), payload = try decode(vector)
        let signature = try XCTUnwrap(vector["signature"] as? String)
        let key = try XCTUnwrap(PrivateKey(data: Data(repeating: 0, count: 31) + Data([2])))
        let json = try EquityCowOrderCodec.typedJSON(payload, consent: review(payload), wallet: wallet(payload), now: now)
        let wrong = EthereumMessageSigner.signTypedMessage(privateKey: key, messageJson: json)
        let personalSignature = try XCTUnwrap(vector["ethSignSignature"] as? String)
        for value in ["0x", signature + "00", "0x" + String(repeating: "0", count: 128) + "1b",
                      String(signature.prefix(66)) + String(repeating: "f", count: 64) + "1b", wrong] {
            XCTAssertThrowsError(try EquityCowOrderCodec.verifySignature(value, payload: payload,
                consent: review(payload), wallet: wallet(payload), now: now))
        }
        XCTAssertThrowsError(try EquityCowOrderCodec.verifySignature(personalSignature, payload: payload,
            consent: review(payload), wallet: wallet(payload), now: now))
    }

    private func vectors() throws -> [[String: Any]] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "evm-equity-signing", withExtension: "json"))
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(value["vectors"] as? [[String: Any]])
    }
    private func root(_ vector: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(vector["payload"] as? [String: Any])
    }
    private func decode(_ vector: [String: Any]) throws -> EquityCowSigningPayload {
        try EquityCowSigningPayload.decode(JSONSerialization.data(withJSONObject: root(vector)))
    }
    private func encode(_ root: [String: Any], consent: EquityCowConsent, wallet: DeviceWalletSummary) throws -> String {
        let payload = try EquityCowSigningPayload.decode(JSONSerialization.data(withJSONObject: root))
        return try EquityCowOrderCodec.typedJSON(payload, consent: consent, wallet: wallet, now: now)
    }
    private func wallet(_ p: EquityCowSigningPayload) -> DeviceWalletSummary {
        DeviceWalletSummary(accountID: p.prepared.account, address: p.prepared.owner, recoveryVerified: true)
    }
    private func review(_ value: EquityCowSigningPayload) -> EquityCowConsent {
        let p = value.prepared, i = p.instrument
        return EquityCowConsent(intentID: p.intentId, version: p.intentVersion, accountID: p.account, owner: p.owner,
            assetID: i.assetId, symbol: i.symbol, network: i.network, token: i.token,
            inputAmountRaw: p.order.sellAmount, minimumOutputAmountRaw: p.order.buyAmount, fingerprint: p.fingerprint,
            preparationHash: value.preparationHash, orderUID: p.orderUid, expiresAt: p.expiresAt)
    }
}
