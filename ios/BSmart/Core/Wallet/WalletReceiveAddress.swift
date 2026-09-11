import Foundation
import WalletCore

struct WalletReceiveAddress: Hashable, Sendable {
    let value: String

    init(owner: String) throws {
        guard TradingWalletChallenge.validAddress(owner),
              owner != "0x" + String(repeating: "0", count: 40),
              let address = AnyAddress(string: owner, coin: .ethereum),
              address.data.count == 20, address.description.lowercased() == owner else {
            throw DeviceWalletError.invalidProof
        }
        value = address.description
    }
}
