import Foundation
import MessagePack
import WalletCore

// Fixed mainnet L1 order scheme. No generic action input, private-key access or network submission.
enum HyperliquidOrderCodec {
    static func messagePack(_ order: HyperliquidOrderIntent) throws -> Data {
        var writer = MessagePackWriter()
        try writer.packDictionaryHeader(count: order.builderFee == nil ? 3 : 4)
        try writer.pack("type")
        try writer.pack("order")
        try writer.pack("orders")
        try writer.packArrayHeader(count: 1)
        try writer.packDictionaryHeader(count: 7)
        try writer.pack("a")
        writer.pack(order.market.asset)
        try writer.pack("b")
        writer.pack(order.side == .buy)
        try writer.pack("p")
        try writer.pack(order.limitPrice.wire)
        try writer.pack("s")
        try writer.pack(order.size.wire)
        try writer.pack("r")
        writer.pack(order.reduceOnly)
        try writer.pack("t")
        try writer.packDictionaryHeader(count: 1)
        try writer.pack("limit")
        try writer.packDictionaryHeader(count: 1)
        try writer.pack("tif")
        try writer.pack("Ioc")
        try writer.pack("c")
        try writer.pack(order.cloid)
        try writer.pack("grouping")
        try writer.pack("na")
        if let fee = order.builderFee {
            try writer.pack("builder")
            try writer.packDictionaryHeader(count: 2)
            try writer.pack("b")
            try writer.pack(fee.address)
            try writer.pack("f")
            writer.pack(fee.tenthsOfBasisPoint)
        }
        return writer.data
    }

    static func actionHash(_ order: HyperliquidOrderIntent) throws -> Data {
        var payload = try messagePack(order)
        var nonce = order.nonce.bigEndian
        withUnsafeBytes(of: &nonce) { payload.append(contentsOf: $0) }
        payload.append(0) // No vault/subaccount.
        payload.append(0) // Optional expiresAfter discriminator, not a MessagePack field.
        var expiry = order.expiresAfter.bigEndian
        withUnsafeBytes(of: &expiry) { payload.append(contentsOf: $0) }
        return Hash.keccak256(data: payload)
    }

    static func typedJSON(_ order: HyperliquidOrderIntent) throws -> String {
        try typedJSON(actionHash: actionHash(order))
    }

    static func typedJSON(actionHash: Data) throws -> String {
        let payload: [String: Any] = [
            "domain": ["name": "Exchange", "version": "1", "chainId": 1337,
                       "verifyingContract": "0x0000000000000000000000000000000000000000"],
            "types": [
                "EIP712Domain": fields([("name", "string"), ("version", "string"),
                                       ("chainId", "uint256"), ("verifyingContract", "address")]),
                "Agent": fields([("source", "string"), ("connectionId", "bytes32")])
            ],
            "primaryType": "Agent",
            "message": ["source": "a", "connectionId": FundingHex.encode(actionHash)]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else { throw HyperliquidExecutionError.invalidIntent }
        return json
    }

    static func signingDigest(_ order: HyperliquidOrderIntent) throws -> Data {
        let digest = EthereumAbi.encodeTyped(messageJson: try typedJSON(order))
        guard digest.count == 32 else { throw HyperliquidExecutionError.invalidIntent }
        return digest
    }

    static func envelope(_ order: HyperliquidOrderIntent, signature: String) throws -> Data {
        do {
            guard signature.count == 132, let bytes = FundingHex.decode(signature) else {
                throw HyperliquidExecutionError.invalidSignature
            }
            let parsed = try FundingEthereumSignature(bytes, encoding: .legacy)
            _ = try parsed.recover(digest: signingDigest(order), owner: order.owner)
            var action: [String: Any] = ["type": "order", "orders": [[
                    "a": order.market.asset, "b": order.side == .buy,
                    "p": order.limitPrice.wire, "s": order.size.wire,
                    "r": order.reduceOnly, "t": ["limit": ["tif": "Ioc"]], "c": order.cloid
                ]], "grouping": "na"]
            if let fee = order.builderFee { action["builder"] = ["b": fee.address, "f": fee.tenthsOfBasisPoint] }
            let payload: [String: Any] = [
                "action": action,
                "nonce": order.nonce, "expiresAfter": order.expiresAfter,
                "signature": ["r": FundingHex.encode(parsed.r), "s": FundingHex.encode(parsed.s),
                              "v": Int(parsed.parity + 27)]
            ]
            return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        } catch { throw HyperliquidExecutionError.invalidSignature }
    }

    private static func fields(_ values: [(String, String)]) -> [[String: String]] {
        values.map { ["name": $0.0, "type": $0.1] }
    }
}
