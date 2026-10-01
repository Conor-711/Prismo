import BigInt
import Foundation
import WalletCore

// Fixed CoW EIP-712 only. No generic typed JSON, wallet keys or broadcasting.
enum EquityCowOrderCodec {
    private static let settlement = "0x9008D19f58AAbD9eD0D60971565AA8510560ab41"
    private static let zeroHash = "0x" + String(repeating: "0", count: 64)

    static func typedJSON(_ payload: EquityCowSigningPayload, consent: EquityCowConsent,
                          wallet: DeviceWalletSummary, now: Date) throws -> String {
        try validate(payload, consent: consent, wallet: wallet, now: now)
        let p = payload.prepared, o = p.order
        let value: [String: Any] = [
            "domain": ["name": "Gnosis Protocol", "version": "v2", "chainId": p.instrument.chainId,
                       "verifyingContract": settlement],
            "types": [
                "EIP712Domain": fields([("name", "string"), ("version", "string"),
                                        ("chainId", "uint256"), ("verifyingContract", "address")]),
                "Order": fields([("sellToken", "address"), ("buyToken", "address"), ("receiver", "address"),
                                 ("sellAmount", "uint256"), ("buyAmount", "uint256"), ("validTo", "uint32"),
                                 ("appData", "bytes32"), ("feeAmount", "uint256"), ("kind", "string"),
                                 ("partiallyFillable", "bool"), ("sellTokenBalance", "string"), ("buyTokenBalance", "string")])
            ],
            "primaryType": "Order",
            "message": ["sellToken": o.sellToken, "buyToken": o.buyToken, "receiver": o.receiver,
                        "sellAmount": o.sellAmount, "buyAmount": o.buyAmount, "validTo": o.validTo,
                        "appData": zeroHash, "feeAmount": "0", "kind": "sell", "partiallyFillable": false,
                        "sellTokenBalance": "erc20", "buyTokenBalance": "erc20"]
        ]
        let bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard let json = String(data: bytes, encoding: .utf8) else { throw EquityCowCodecError.invalidPayload }
        // Independent native EIP-712 implementation must reproduce SDK digest
        // and UID (digest + owner + uint32 big-endian validTo).
        let digest = EthereumAbi.encodeTyped(messageJson: json)
        guard digest.count == 32, FundingHex.encode(digest) == p.orderDigest,
              let owner = FundingHex.decode(p.owner), owner.count == 20 else { throw EquityCowCodecError.invalidBinding }
        var validTo = o.validTo.bigEndian
        let uid = digest + owner + withUnsafeBytes(of: &validTo) { Data($0) }
        guard FundingHex.encode(uid) == p.orderUid else { throw EquityCowCodecError.invalidBinding }
        return json
    }

    static func verifySignature(_ signature: String, payload: EquityCowSigningPayload,
                                consent: EquityCowConsent, wallet: DeviceWalletSummary, now: Date) throws -> String {
        let json = try typedJSON(payload, consent: consent, wallet: wallet, now: now)
        do {
            let parsed = try EmbeddedWalletSignature.parse(signature)
            _ = try parsed.recover(digest: EthereumAbi.encodeTyped(messageJson: json), owner: wallet.address)
            return try EmbeddedWalletSignature.legacy(signature)
        } catch { throw EquityCowCodecError.invalidSignature }
    }

    private static func validate(_ payload: EquityCowSigningPayload, consent: EquityCowConsent,
                                 wallet: DeviceWalletSummary, now: Date) throws {
        let p = payload.prepared, i = p.instrument, o = p.order, d = p.domain
        let chain: Int, usdc: String
        switch i.network {
        case "Ethereum": chain = 1; usdc = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
        case "Ink": chain = 57073; usdc = "0x2d270e6886d130d724215a266106e6832161eaed"
        default: throw EquityCowCodecError.invalidBinding
        }
        guard payload.schema == "equity_signing_v1", payload.state == "signing", !payload.executionEnabled,
              p.schema == "cow_order_v1", p.side == "buy", p.intentId == consent.intentID,
              p.intentVersion == consent.version, (1...2_147_483_645).contains(p.intentVersion),
              p.account == consent.accountID, p.account == wallet.accountID,
              address(p.owner), p.owner == wallet.address, p.owner == consent.owner,
              p.fingerprint == consent.fingerprint, hex(p.fingerprint, bytes: 32, prefix: false),
              payload.preparationHash == consent.preparationHash, hex(payload.preparationHash, bytes: 32, prefix: false),
              p.orderUid == consent.orderUID, p.expiresAt == consent.expiresAt,
              i.assetId == consent.assetID, i.symbol == consent.symbol, !i.symbol.isEmpty,
              i.network == consent.network, i.token == consent.token, address(i.token), i.token != usdc,
              i.chainId == chain, i.usdc == usdc, i.tokenVariant == "raw", i.maxLeverage == 1,
              d.name == "Gnosis Protocol", d.version == "v2", d.chainId == chain, d.verifyingContract == settlement,
              o.sellToken == usdc, o.buyToken == i.token, o.receiver == p.owner,
              o.sellAmount == consent.inputAmountRaw, o.buyAmount == consent.minimumOutputAmountRaw,
              positiveUInt256(o.sellAmount), positiveUInt256(o.buyAmount), o.validTo > 0,
              o.kind == "sell", !o.partiallyFillable, o.feeAmount == "0", o.appData == zeroHash,
              o.sellTokenBalance == "erc20", o.buyTokenBalance == "erc20",
              hex(p.orderDigest, bytes: 32), hex(p.orderUid, bytes: 56) else { throw EquityCowCodecError.invalidBinding }
        guard let started = date(payload.signingStartedAt), let expiry = date(p.expiresAt),
              now.timeIntervalSince1970.isFinite, started <= now, now.timeIntervalSince(started) < 30,
              expiry.timeIntervalSince(now) > 5, expiry.timeIntervalSince(now) <= 600,
              expiry.timeIntervalSince1970 <= Double(o.validTo) else { throw EquityCowCodecError.expired }
    }

    private static func fields(_ values: [(String, String)]) -> [[String: String]] {
        values.map { ["name": $0.0, "type": $0.1] }
    }
    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
    private static func address(_ value: String) -> Bool {
        hex(value, bytes: 20) && value != "0x" + String(repeating: "0", count: 40)
    }
    private static func hex(_ value: String, bytes: Int, prefix: Bool = true) -> Bool {
        if prefix && !value.hasPrefix("0x") { return false }
        let digits = prefix ? value.dropFirst(2) : value[...]
        return digits.count == bytes * 2 && digits.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func positiveUInt256(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 78, value.first != "0",
              value.utf8.allSatisfy({ (48...57).contains($0) }), let number = BigUInt(value) else { return false }
        return number > 0 && number.bitWidth <= 256
    }
}
