import Foundation
import MessagePack
import WalletCore

protocol HyperliquidLeverageSigning: Sendable {
    func signLeverage(_ permit: HyperliquidLeveragePermit, lease: FundingSigningLease) async throws -> String
}

// Fixed updateLeverage action, with the same ordered MessagePack/L1 scheme as the official SDK.
enum HyperliquidLeverageCodec {
    static func actionHash(_ update: HyperliquidLeverageUpdate) throws -> Data {
        try update.validate(wallet: update.wallet)
        var writer = MessagePackWriter()
        try writer.packDictionaryHeader(count: 4)
        try writer.pack("type"); try writer.pack("updateLeverage")
        try writer.pack("asset"); writer.pack(update.market.asset)
        try writer.pack("isCross"); writer.pack(update.isCross)
        try writer.pack("leverage"); writer.pack(update.leverage)
        var data = writer.data, nonce = update.nonce.bigEndian, expiry = update.expiresAfter.bigEndian
        withUnsafeBytes(of: &nonce) { data.append(contentsOf: $0) }
        data.append(0); data.append(0)
        withUnsafeBytes(of: &expiry) { data.append(contentsOf: $0) }
        return Hash.keccak256(data: data)
    }

    static func typedJSON(_ update: HyperliquidLeverageUpdate) throws -> String {
        try HyperliquidOrderCodec.typedJSON(actionHash: actionHash(update))
    }

    static func envelope(_ update: HyperliquidLeverageUpdate, signature: String) throws -> Data {
        guard signature.count == 132, let bytes = FundingHex.decode(signature) else {
            throw HyperliquidExecutionError.invalidSignature
        }
        let parsed = try FundingEthereumSignature(bytes, encoding: .legacy)
        let digest = EthereumAbi.encodeTyped(messageJson: try typedJSON(update))
        _ = try parsed.recover(digest: digest, owner: update.owner)
        return try JSONSerialization.data(withJSONObject: [
            "action": ["type": "updateLeverage", "asset": update.market.asset,
                       "isCross": update.isCross, "leverage": update.leverage],
            "nonce": update.nonce, "expiresAfter": update.expiresAfter,
            "signature": ["r": FundingHex.encode(parsed.r), "s": FundingHex.encode(parsed.s), "v": Int(parsed.parity + 27)]
        ], options: [.sortedKeys])
    }

    static func sign(_ update: HyperliquidLeverageUpdate, entropy: Data, wallet: DeviceWalletSummary, now: Date) throws -> String {
        try update.validate(wallet: wallet, now: now)
        guard entropy.count == 32, let hd = HDWallet(entropy: entropy, passphrase: ""),
              let key = hd.getKey(coin: .ethereum, derivationPath: DeviceWalletCryptography.derivationPath),
              CoinType.ethereum.deriveAddress(privateKey: key).lowercased() == wallet.address else {
            throw DeviceWalletError.invalidProof
        }
        let raw = EthereumMessageSigner.signTypedMessage(privateKey: key, messageJson: try typedJSON(update))
        let signature = raw.hasPrefix("0x") ? raw : "0x" + raw
        _ = try envelope(update, signature: signature)
        return signature
    }
}
