import Foundation
import Security
import WalletCore

enum DeviceWalletCryptography {
    static let derivationPath = "m/44'/60'/0'/0/0"

    static func generateEntropy() throws -> Data {
        var bytes = Data(count: 32)
        let result = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard result == errSecSuccess else { throw DeviceWalletError.storage }
        return bytes
    }

    static func address(entropy: Data) throws -> String {
        let wallet = try wallet(entropy: entropy)
        guard let key = wallet.getKey(coin: .ethereum, derivationPath: derivationPath) else {
            throw DeviceWalletError.storage
        }
        let result = CoinType.ethereum.deriveAddress(privateKey: key).lowercased()
        guard TradingWalletChallenge.validAddress(result) else { throw DeviceWalletError.storage }
        return result
    }

    static func recoveryWords(entropy: Data) throws -> [String] {
        try wallet(entropy: entropy).mnemonic.split(separator: " ").map(String.init)
    }

    static func entropy(phrase: String) throws -> Data {
        // Only this app's 24-word English, empty-passphrase format is recoverable here.
        guard phrase.utf8.count <= 512 else { throw DeviceWalletError.wrongRecovery }
        let words = phrase.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        guard words.count == 24, words.allSatisfy({ !$0.isEmpty && $0.allSatisfy { ("a"..."z").contains($0) } }),
              let wallet = HDWallet(mnemonic: words.joined(separator: " "), passphrase: ""),
              wallet.entropy.count == 32 else { throw DeviceWalletError.wrongRecovery }
        return wallet.entropy
    }

    static func bindingSignature(entropy: Data, challenge: TradingWalletChallenge, accountID: UUID, now: Date = Date()) throws -> String {
        let address = try address(entropy: entropy)
        let message = try challenge.message(accountID: accountID, address: address, now: now)
        let wallet = try wallet(entropy: entropy)
        guard let key = wallet.getKey(coin: .ethereum, derivationPath: derivationPath) else {
            throw DeviceWalletError.storage
        }
        let signed = EthereumMessageSigner.signMessage(privateKey: key, message: message)
        let result = signed.hasPrefix("0x") ? signed : "0x" + signed
        guard result.count == 132, result.dropFirst(2).allSatisfy({ $0.isHexDigit }),
              ["1b", "1c"].contains(String(result.suffix(2)).lowercased()) else {
            throw DeviceWalletError.invalidProof
        }
        return result
    }

    private static func wallet(entropy: Data) throws -> HDWallet {
        guard entropy.count == 32, let wallet = HDWallet(entropy: entropy, passphrase: "") else {
            throw DeviceWalletError.storage
        }
        return wallet
    }
}
