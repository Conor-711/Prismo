import Foundation
import WalletCore

protocol HyperliquidDeviceSigning: Sendable {
    func signOrder(_ permit: HyperliquidOrderSigningPermit, lease: FundingSigningLease) async throws -> String
}

enum HyperliquidDeviceCryptography {
    static func sign(order: HyperliquidOrderIntent, entropy: Data, wallet: DeviceWalletSummary, now: Date) throws -> String {
        guard wallet.canAuthorizeTransactions, order.accountID == wallet.accountID, order.owner == wallet.address,
              order.builderFee == nil, now.timeIntervalSince1970.isFinite,
              Double(order.nonce) <= now.timeIntervalSince1970 * 1000 + 1000,
              now.timeIntervalSince1970 * 1000 < Double(order.expiresAfter),
              entropy.count == 32, let hd = HDWallet(entropy: entropy, passphrase: ""),
              let key = hd.getKey(coin: .ethereum, derivationPath: DeviceWalletCryptography.derivationPath),
              CoinType.ethereum.deriveAddress(privateKey: key).lowercased() == wallet.address else {
            throw DeviceWalletError.invalidProof
        }
        let value = EthereumMessageSigner.signTypedMessage(privateKey: key, messageJson: try HyperliquidOrderCodec.typedJSON(order))
        let signature = value.hasPrefix("0x") ? value : "0x" + value
        _ = try HyperliquidOrderCodec.envelope(order, signature: signature)
        return signature
    }
}
