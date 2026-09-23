import Foundation
import Security

enum CCTPArbitrumRoute {
    static let sourceDomain: UInt32 = 3
    static let destinationDomain: UInt32 = 19
    static let destinationDex: UInt32 = 0
    static let finalityThreshold: UInt32 = 1000
    static let extensionAddress = "0xa95d9c1f655341597c94393fddc30cf3c08e4fce"
    static let forwarderAddress = "0xb21d281dedb17ae5b501f6aa8256fe38c4e45757"
    static let coreDepositWallet = "0x6b9e773128f453f5c2c60935ee2de2cbc5390a24"
    static let destinationUSDC = "0xb88339cb7199b77e23db6e890353e22632ba630f"
    static let coreTokenSystemAddress = "0x2000000000000000000000000000000000000000"
    static let tokenMessenger = "0x28b5a0e9c621a5badaa536219b3a228c8168cf5d"
    static let messageTransmitter = "0x81d40f21f12a8f0e3252bccb954d722d4c464b64"
    static let tokenMinter = "0xfd78ee919681417d192449715b2594ab58f5d002"
}

struct CCTPDepositPlan: Sendable {
    let accountID: UUID
    let owner: String
    let quote: CCTPDepositQuote
    let authorizationNonce: Data
    let validAfter: UInt64
    let validBefore: UInt64
    let createdAt: Date

    init(wallet: DeviceWalletSummary, quote: CCTPDepositQuote, now: Date = Date()) throws {
        var nonce = Data(count: 32)
        let result = nonce.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
        guard result == errSecSuccess else { throw CCTPFundingError.invalidPlan }
        try self.init(wallet: wallet, quote: quote, now: now, nonce: nonce)
    }

    // Deterministic entropy injection stays internal for independent protocol vectors.
    init(wallet: DeviceWalletSummary, quote: CCTPDepositQuote, now: Date, nonce: Data) throws {
        let seconds = now.timeIntervalSince1970
        guard wallet.canAuthorizeTransactions, TradingWalletChallenge.validAddress(wallet.address),
              wallet.address == wallet.address.lowercased(), nonce.count == 32,
              seconds.isFinite, seconds >= 30, seconds < 4_102_444_800,
              now < quote.expiresAt, quote.expiresAt.timeIntervalSince(now) <= CCTPFeeSchedule.lifetime else {
            throw CCTPFundingError.invalidPlan
        }
        accountID = wallet.accountID
        owner = wallet.address
        self.quote = quote
        authorizationNonce = nonce
        validAfter = UInt64(seconds) - 30
        validBefore = UInt64(seconds) + 300
        createdAt = now
    }

    func validate(wallet: DeviceWalletSummary, now: Date) throws {
        try validateAuthorization(wallet: wallet, now: now)
        guard now < quote.expiresAt else { throw CCTPFundingError.expiredQuote }
    }

    func validateAuthorization(wallet: DeviceWalletSummary, now: Date) throws {
        guard wallet.accountID == accountID, wallet.address == owner, wallet.canAuthorizeTransactions,
              now >= createdAt,
              now.timeIntervalSince1970 >= TimeInterval(validAfter),
              now.timeIntervalSince1970 < TimeInterval(validBefore) else { throw CCTPFundingError.invalidPlan }
    }

    var hookData: Data {
        // Circle's fixed 56-byte version-0 header + this owner's address + default perps DEX.
        var result = Data("cctp-forward".utf8)
        result.append(Data(repeating: 0, count: 12))
        result.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 24])
        result.append(FundingHex.decode(owner)!) // Owner was validated on construction.
        result.append(contentsOf: [0, 0, 0, 0])
        return result
    }
}

enum FundingHex {
    static func decode(_ value: String) -> Data? {
        guard value.hasPrefix("0x"), value.utf8.count % 2 == 0,
              value.dropFirst(2).utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        let characters = Array(value.dropFirst(2))
        var result = Data()
        for index in stride(from: 0, to: characters.count, by: 2) {
            guard let byte = UInt8(String(characters[index...index + 1]), radix: 16) else { return nil }
            result.append(byte)
        }
        return result
    }

    static func encode(_ data: Data) -> String { "0x" + data.map { String(format: "%02x", $0) }.joined() }
}
