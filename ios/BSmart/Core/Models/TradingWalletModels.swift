import Foundation

struct TradingWalletRegistration: Codable, Equatable, Sendable {
    let accountId: UUID
    let address: String?
    var capabilities: TradingWalletCapabilities? = nil
}

struct TradingWalletCapabilities: Codable, Equatable, Sendable {
    let depositsEnabled: Bool
    let tradingEnabled: Bool
    let withdrawalsEnabled: Bool
    var acrossWithdrawalsEnabled: Bool? = nil
}

extension TradingWalletRegistration {
    private enum CodingKeys: String, CodingKey { case accountId, address, capabilities }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(accountId, forKey: .accountId)
        if let address { try values.encode(address, forKey: .address) }
        else { try values.encodeNil(forKey: .address) }
        try values.encodeIfPresent(capabilities, forKey: .capabilities)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard values.contains(.address) else {
            throw DecodingError.keyNotFound(CodingKeys.address, .init(codingPath: decoder.codingPath,
                                                                     debugDescription: "Missing wallet registration state"))
        }
        accountId = try values.decode(UUID.self, forKey: .accountId)
        address = try values.decodeIfPresent(String.self, forKey: .address)
        capabilities = try values.decodeIfPresent(TradingWalletCapabilities.self, forKey: .capabilities)
        guard address.map(TradingWalletChallenge.validAddress) ?? true else { throw DeviceWalletError.invalidProof }
    }
}

struct TradingWalletChallenge: Codable, Sendable {
    let id: UUID
    let accountId: UUID
    let address: String
    let nonce: String
    let issuedAt: Date
    let expiresAt: Date

    func message(accountID: UUID, address expected: String, now: Date = Date()) throws -> String {
        guard accountId == accountID, address == expected, Self.validAddress(address),
              nonce.count == 64, nonce.allSatisfy({ "0123456789abcdef".contains($0) }),
              issuedAt.timeIntervalSince1970.rounded(.down) == issuedAt.timeIntervalSince1970,
              expiresAt.timeIntervalSince1970.rounded(.down) == expiresAt.timeIntervalSince1970,
              issuedAt <= now.addingTimeInterval(30), expiresAt > now,
              expiresAt > issuedAt, expiresAt.timeIntervalSince(issuedAt) <= 300,
              now.timeIntervalSince(issuedAt) < 300 else { throw DeviceWalletError.invalidProof }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return [
            "bSmart wallet binding v1",
            "Audience: https://api.bsmart.today/v1/auth/wallet",
            "Account: \(accountId.uuidString.lowercased())",
            "Address: \(address)",
            "Chain ID: 42161",
            "Challenge: \(id.uuidString.lowercased())",
            "Nonce: \(nonce)",
            "Issued At: \(formatter.string(from: issuedAt))",
            "Expires At: \(formatter.string(from: expiresAt))",
            "This only links your wallet to bSmart. It does not authorize a transfer or trade."
        ].joined(separator: "\n")
    }

    static func validAddress(_ value: String) -> Bool {
        value.count == 42 && value.hasPrefix("0x") &&
        value.dropFirst(2).allSatisfy { "0123456789abcdef".contains($0) } &&
        value.dropFirst(2).contains { $0 != "0" }
    }
}

struct DeviceWalletSummary: Equatable, Sendable {
    let accountID: UUID
    let address: String
    let recoveryVerified: Bool
    var provider: TradingWalletProvider = .device
}

enum TradingWalletProvider: String, Sendable {
    case device, privy
}

enum DeviceWalletError: Error, LocalizedError {
    case locked, storage, alreadyExists, recoveryRequired, wrongRecovery, invalidProof, accountChanged, cancelled

    var errorDescription: String? {
        switch self {
        case .locked: return "Unlock your device and enable a passcode to use this wallet.".bSmartLocalized
        case .storage: return "The wallet could not be stored securely. No funds have been moved.".bSmartLocalized
        case .alreadyExists: return "A wallet already exists on this device. Unlock it to continue.".bSmartLocalized
        case .recoveryRequired: return "Restore the wallet already linked to this account.".bSmartLocalized
        case .wrongRecovery: return "The recovery phrase does not match this wallet.".bSmartLocalized
        case .invalidProof: return "Wallet verification failed. Please try again.".bSmartLocalized
        case .accountChanged: return "Your account changed. Open the wallet again.".bSmartLocalized
        case .cancelled: return nil
        }
    }
}
