import Foundation
import WalletCore

enum EmbeddedWalletSignature {
    // Provider RPCs may return v=0/1 or 27/28; normalize only at this boundary.
    static func parse(_ value: String) throws -> FundingEthereumSignature {
        guard let bytes = FundingHex.decode(value), let v = bytes.last else { throw DeviceWalletError.invalidProof }
        return try FundingEthereumSignature(bytes, encoding: v < 2 ? .parity : .legacy)
    }

    static func legacy(_ value: String) throws -> String {
        let signature = try parse(value)
        return FundingHex.encode(signature.r + signature.s + Data([signature.parity + 27]))
    }

    static func binding(_ value: String, message: String, owner: String) throws -> String {
        let signature = try parse(value)
        let bytes = Data(message.utf8)
        let digest = Hash.keccak256(data: Data("\u{19}Ethereum Signed Message:\n\(bytes.count)".utf8) + bytes)
        _ = try signature.recover(digest: digest, owner: owner)
        return try legacy(value)
    }
}
