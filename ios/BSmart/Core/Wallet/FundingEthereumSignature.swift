import Foundation
import WalletCore

// EIP-3009 uses v=27/28; a type-2 transaction uses yParity=0/1. Never guess which was supplied.
struct FundingEthereumSignature {
    enum RecoveryEncoding { case legacy, parity }
    let r: Data
    let s: Data
    let parity: UInt8

    init(_ bytes: Data, encoding: RecoveryEncoding) throws {
        guard bytes.count == 65, let recovery = bytes.last else { throw CCTPFundingError.invalidPlan }
        switch encoding {
        case .legacy:
            guard recovery == 27 || recovery == 28 else { throw CCTPFundingError.invalidPlan }
            parity = recovery - 27
        case .parity:
            guard recovery == 0 || recovery == 1 else { throw CCTPFundingError.invalidPlan }
            parity = recovery
        }
        r = Data(bytes.prefix(32))
        s = Data(bytes.dropFirst(32).prefix(32))
        let order = FundingHex.decode("0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141")!
        let halfOrder = FundingHex.decode("0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0")!
        guard !r.allSatisfy({ $0 == 0 }), r.lexicographicallyPrecedes(order),
              !s.allSatisfy({ $0 == 0 }), !halfOrder.lexicographicallyPrecedes(s) else {
            throw CCTPFundingError.invalidPlan
        }
    }

    var compilerBytes: Data { r + s + Data([parity]) }

    func recover(digest: Data, owner: String) throws -> PublicKey {
        let key = try recover(digest: digest)
        guard AnyAddress(publicKey: key, coin: .ethereum).description.lowercased() == owner else {
            throw CCTPFundingError.invalidPlan
        }
        return key
    }

    func recover(digest: Data) throws -> PublicKey {
        guard digest.count == 32,
              let key = PublicKey.recover(signature: r + s + Data([parity + 27]), message: digest) else {
            throw CCTPFundingError.invalidPlan
        }
        return key
    }
}
