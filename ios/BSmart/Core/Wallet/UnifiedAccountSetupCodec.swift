import Foundation
import WalletCore

protocol UnifiedAccountSetupSigning: Sendable {
    func signUnifiedAccount(_ permit: UnifiedAccountSetupPermit, lease: FundingSigningLease) async throws -> String
}

enum UnifiedAccountSetupCodec {
    static func typedJSON(_ setup: UnifiedAccountSetup) throws -> String {
        try setup.validate(wallet: setup.wallet)
        let fields = [("hyperliquidChain", "string"), ("user", "address"), ("abstraction", "string"), ("nonce", "uint64")]
        let domain = [("name", "string"), ("version", "string"), ("chainId", "uint256"), ("verifyingContract", "address")]
        let data = try JSONSerialization.data(withJSONObject: [
            "domain": ["name": "HyperliquidSignTransaction", "version": "1", "chainId": 42161,
                       "verifyingContract": "0x0000000000000000000000000000000000000000"],
            "types": ["EIP712Domain": domain.map { ["name": $0.0, "type": $0.1] },
                      "HyperliquidTransaction:UserSetAbstraction": fields.map { ["name": $0.0, "type": $0.1] }],
            "primaryType": "HyperliquidTransaction:UserSetAbstraction", "message": message(setup)
        ], options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else { throw DeviceWalletError.invalidProof }
        return json
    }

    static func envelope(_ setup: UnifiedAccountSetup, signature: String) throws -> Data {
        guard let data = FundingHex.decode(signature), data.count == 65 else { throw DeviceWalletError.invalidProof }
        let parsed = try FundingEthereumSignature(data, encoding: .legacy)
        let digest = EthereumAbi.encodeTyped(messageJson: try typedJSON(setup))
        _ = try parsed.recover(digest: digest, owner: setup.owner)
        var action = message(setup)
        action["type"] = "userSetAbstraction"; action["signatureChainId"] = "0xa4b1"
        return try JSONSerialization.data(withJSONObject: ["action": action, "nonce": setup.nonce,
            "signature": ["r": FundingHex.encode(parsed.r), "s": FundingHex.encode(parsed.s), "v": Int(parsed.parity + 27)]],
            options: [.sortedKeys])
    }

    static func sign(_ setup: UnifiedAccountSetup, entropy: Data, wallet: DeviceWalletSummary, now: Date) throws -> String {
        try setup.validate(wallet: wallet, now: now)
        guard entropy.count == 32, let hd = HDWallet(entropy: entropy, passphrase: ""),
              let key = hd.getKey(coin: .ethereum, derivationPath: DeviceWalletCryptography.derivationPath),
              CoinType.ethereum.deriveAddress(privateKey: key).lowercased() == wallet.address else {
            throw DeviceWalletError.invalidProof
        }
        let value = EthereumMessageSigner.signTypedMessage(privateKey: key, messageJson: try typedJSON(setup))
        let signature = value.hasPrefix("0x") ? value : "0x" + value
        _ = try envelope(setup, signature: signature)
        return signature
    }

    private static func message(_ setup: UnifiedAccountSetup) -> [String: Any] {
        ["hyperliquidChain": "Mainnet", "user": setup.owner, "abstraction": "unifiedAccount", "nonce": setup.nonce]
    }
}
