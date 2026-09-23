import Foundation

// Existing device keys stay local. Only unbound accounts can create a Privy wallet.
@MainActor
final class HybridTradingWalletVault: DeviceWalletVault, TradingWalletSigning {
    let local: any DeviceWalletVault & TradingWalletSigning
    let embedded: any EmbeddedWalletClient
    let clock: @Sendable () -> Date
    private var resolved: [UUID: DeviceWalletSummary] = [:]

    init(local: any DeviceWalletVault & TradingWalletSigning = KeychainDeviceWalletVault(),
         embedded: any EmbeddedWalletClient, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.local = local; self.embedded = embedded; self.clock = clock
    }

    func summary(accountID: UUID, registeredAddress: String?) async throws -> DeviceWalletSummary? {
        resolved[accountID] = nil
        if let wallet = try await local.summary(accountID: accountID, registeredAddress: registeredAddress),
           registeredAddress == nil || wallet.address == registeredAddress {
            resolved[accountID] = wallet
            return wallet
        }
        let wallet = try await embedded.resolve(accountID: accountID, address: registeredAddress, create: false)
        try validate(wallet, accountID: accountID, address: registeredAddress)
        resolved[accountID] = wallet
        return wallet
    }

    func create(accountID: UUID) async throws -> DeviceWalletSummary {
        guard resolved[accountID] == nil else { throw DeviceWalletError.alreadyExists }
        guard let wallet = try await embedded.resolve(accountID: accountID, address: nil, create: true) else {
            throw EmbeddedWalletError.unavailable
        }
        try validate(wallet, accountID: accountID, address: nil)
        resolved[accountID] = wallet
        return wallet
    }

    private func validate(_ wallet: DeviceWalletSummary?, accountID: UUID, address: String?) throws {
        guard let wallet else { return }
        guard wallet.accountID == accountID, wallet.provider == .privy, !wallet.recoveryVerified,
              TradingWalletChallenge.validAddress(wallet.address), address == nil || wallet.address == address else {
            throw DeviceWalletError.invalidProof
        }
    }

    func signBinding(accountID: UUID, challenge: TradingWalletChallenge) async throws -> String {
        guard let wallet = resolved[accountID], wallet.address == challenge.address else { throw DeviceWalletError.locked }
        let message = try challenge.message(accountID: accountID, address: wallet.address, now: clock())
        if wallet.provider == .device { return try await local.signBinding(accountID: accountID, challenge: challenge) }
        let signature = try await embedded.personalSign(accountID: accountID, address: wallet.address, message: message)
        _ = try challenge.message(accountID: accountID, address: wallet.address, now: clock())
        return try EmbeddedWalletSignature.binding(signature, message: message, owner: wallet.address)
    }

    func recoveryWords(accountID: UUID, address: String) async throws -> [String] {
        try requireLocal(accountID)
        return try await local.recoveryWords(accountID: accountID, address: address)
    }

    func verifyRecovery(accountID: UUID, address: String, phrase: String) async throws -> DeviceWalletSummary {
        try requireLocal(accountID)
        return try await local.verifyRecovery(accountID: accountID, address: address, phrase: phrase)
    }

    func restore(accountID: UUID, address: String, phrase: String) async throws -> DeviceWalletSummary {
        try requireLocal(accountID)
        let wallet = try await local.restore(accountID: accountID, address: address, phrase: phrase)
        resolved[accountID] = wallet
        return wallet
    }

    func userPresenceRequired(accountID: UUID, address: String) async throws -> Bool {
        if resolved[accountID]?.provider == .privy { return false }
        return try await local.userPresenceRequired(accountID: accountID, address: address)
    }

    func setUserPresenceRequired(_ required: Bool, accountID: UUID, address: String) async throws {
        try requireLocal(accountID)
        try await local.setUserPresenceRequired(required, accountID: accountID, address: address)
    }

    private func requireLocal(_ accountID: UUID) throws {
        if resolved[accountID]?.provider == .privy { throw EmbeddedWalletError.unsupportedRecovery }
    }
}
