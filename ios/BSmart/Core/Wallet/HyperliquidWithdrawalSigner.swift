import Foundation
import WalletCore

protocol HyperliquidWithdrawalSigning: Sendable {
    func signWithdrawal(_ permit: HyperliquidWithdrawalSigningPermit, lease: FundingSigningLease) async throws -> String
}

enum HyperliquidWithdrawalCryptography {
    static func sign(intent: HyperliquidWithdrawalIntent, entropy: Data, wallet: DeviceWalletSummary, now: Date) throws -> String {
        try intent.validate(wallet: wallet)
        let age = now.timeIntervalSince1970 * 1000 - Double(intent.nonce)
        guard age.isFinite, age >= -1000, age < 60_000, entropy.count == 32,
              let hd = HDWallet(entropy: entropy, passphrase: ""),
              let key = hd.getKey(coin: .ethereum, derivationPath: DeviceWalletCryptography.derivationPath),
              CoinType.ethereum.deriveAddress(privateKey: key).lowercased() == wallet.address else {
            throw DeviceWalletError.invalidProof
        }
        let value = EthereumMessageSigner.signTypedMessage(privateKey: key, messageJson: try HyperliquidWithdrawalCodec.typedJSON(intent))
        let signature = value.hasPrefix("0x") ? value : "0x" + value
        _ = try HyperliquidWithdrawalCodec.envelope(intent, signature: signature)
        return signature
    }
}
