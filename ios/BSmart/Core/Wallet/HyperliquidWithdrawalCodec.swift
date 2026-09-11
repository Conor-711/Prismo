import Foundation
import WalletCore

// Human-readable user action, not the order codec's MessagePack/Agent scheme.
enum HyperliquidWithdrawalCodec {
    static func typedJSON(_ intent: HyperliquidWithdrawalIntent) throws -> String {
        let fields = [("hyperliquidChain", "string"), ("token", "string"), ("amount", "string"),
                      ("sourceDex", "string"), ("destinationRecipient", "string"), ("addressEncoding", "string"),
                      ("destinationChainId", "uint32"), ("gasLimit", "uint64"), ("data", "bytes"), ("nonce", "uint64")]
        let domain = [("name", "string"), ("version", "string"), ("chainId", "uint256"), ("verifyingContract", "address")]
        let payload: [String: Any] = [
            "domain": ["name": "HyperliquidSignTransaction", "version": "1", "chainId": HyperliquidWithdrawalIntent.signatureChainID,
                       "verifyingContract": "0x0000000000000000000000000000000000000000"],
            "types": ["EIP712Domain": domain.map { ["name": $0.0, "type": $0.1] },
                      "HyperliquidTransaction:SendToEvmWithData": fields.map { ["name": $0.0, "type": $0.1] }],
            "primaryType": "HyperliquidTransaction:SendToEvmWithData", "message": message(intent)
        ]
        let bytes = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let json = String(data: bytes, encoding: .utf8) else { throw HyperliquidWithdrawalError.invalidIntent }
        return json
    }

    static func signingDigest(_ intent: HyperliquidWithdrawalIntent) throws -> Data {
        let digest = EthereumAbi.encodeTyped(messageJson: try typedJSON(intent))
        guard digest.count == 32 else { throw HyperliquidWithdrawalError.invalidIntent }
        return digest
    }

    static func envelope(_ intent: HyperliquidWithdrawalIntent, signature: String) throws -> Data {
        do {
            guard signature.count == 132, let bytes = FundingHex.decode(signature) else {
                throw HyperliquidWithdrawalError.invalidSignature
            }
            let parsed = try FundingEthereumSignature(bytes, encoding: .legacy)
            _ = try parsed.recover(digest: signingDigest(intent), owner: intent.owner)
            var action = message(intent)
            action["type"] = "sendToEvmWithData"
            action["signatureChainId"] = "0xa4b1"
            // expiresAfter is deliberately absent: this user-signed action does not support it.
            return try JSONSerialization.data(withJSONObject: ["action": action, "nonce": intent.nonce,
                "signature": ["r": FundingHex.encode(parsed.r), "s": FundingHex.encode(parsed.s), "v": Int(parsed.parity + 27)]],
                options: [.sortedKeys])
        } catch { throw HyperliquidWithdrawalError.invalidSignature }
    }

    private static func message(_ intent: HyperliquidWithdrawalIntent) -> [String: Any] {
        ["hyperliquidChain": "Mainnet", "token": "USDC", "amount": intent.amount.wire,
         "sourceDex": intent.source.rawValue, "destinationRecipient": intent.recipient, "addressEncoding": "hex",
         "destinationChainId": HyperliquidWithdrawalIntent.destinationDomain, "gasLimit": HyperliquidWithdrawalIntent.gasLimit,
         "data": "0x", "nonce": intent.nonce]
    }
}
