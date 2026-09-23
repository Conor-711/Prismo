import Foundation

protocol DeviceWalletVault: Sendable {
    func summary(accountID: UUID, registeredAddress: String?) async throws -> DeviceWalletSummary?
    func create(accountID: UUID) async throws -> DeviceWalletSummary
    func recoveryWords(accountID: UUID, address: String) async throws -> [String]
    func verifyRecovery(accountID: UUID, address: String, phrase: String) async throws -> DeviceWalletSummary
    func restore(accountID: UUID, address: String, phrase: String) async throws -> DeviceWalletSummary
    func signBinding(accountID: UUID, challenge: TradingWalletChallenge) async throws -> String
    func userPresenceRequired(accountID: UUID, address: String) async throws -> Bool
    func setUserPresenceRequired(_ required: Bool, accountID: UUID, address: String) async throws
}

extension DeviceWalletVault {
    func userPresenceRequired(accountID: UUID, address: String) async throws -> Bool { true }
    func setUserPresenceRequired(_ required: Bool, accountID: UUID, address: String) async throws {
        throw DeviceWalletError.storage
    }
}

struct DeviceWalletRecord: Codable {
    let version: Int
    let accountID: UUID
    let address: String
    var entropy: Data
    var recoveryVerified: Bool
    var userPresenceRequired: Bool? = nil

    func validated(accountID expected: UUID) throws -> DeviceWalletSummary {
        guard version == 1, accountID == expected,
              try DeviceWalletCryptography.address(entropy: entropy) == address else {
            throw DeviceWalletError.storage
        }
        return .init(accountID: accountID, address: address, recoveryVerified: recoveryVerified)
    }

    mutating func eraseTemporaryBytes() { entropy.resetBytes(in: 0..<entropy.count) }
}
