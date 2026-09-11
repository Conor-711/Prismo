import Foundation
import Combine

@MainActor
protocol AccountWalletServicing: AnyObject {
    var walletAccountID: UUID? { get }
    func walletRegistration() async throws -> TradingWalletRegistration
    func walletChallenge(address: String) async throws -> TradingWalletChallenge
    func bindWallet(challenge: TradingWalletChallenge, signature: String) async throws -> TradingWalletRegistration
    func fundingSigningLease(wallet: DeviceWalletSummary) throws -> FundingSigningLease
}

extension AccountWalletServicing {
    func fundingSigningLease(wallet: DeviceWalletSummary) throws -> FundingSigningLease {
        throw FundingJournalError.unavailable
    }
}

enum DeviceWalletState: Equatable {
    case locked
    case loading
    case recoveryRequired(address: String)
    case verified(DeviceWalletSummary)
}

@MainActor
final class DeviceWalletStore: ObservableObject {
    @Published private(set) var state = DeviceWalletState.locked
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    private let service: AccountWalletServicing
    private let vault: DeviceWalletVault
    private var revision = UUID()

    init(service: AccountWalletServicing, vault: DeviceWalletVault = KeychainDeviceWalletVault()) {
        self.service = service
        self.vault = vault
    }

    func lock() {
        revision = UUID()
        state = .locked
        errorMessage = nil
        // An in-flight vault write retains its account scope; don't allow overlapping writes.
    }

    func prepare() async {
        guard !isBusy, let accountID = service.walletAccountID else { return }
        if case .verified(let value) = state, value.accountID == accountID { return }
        let operation = revision
        isBusy = true
        state = .loading
        errorMessage = nil
        defer { isBusy = false }
        do {
            let registered = try await service.walletRegistration()
            try check(accountID, operation)
            guard registered.accountId == accountID,
                  registered.address.map(TradingWalletChallenge.validAddress) ?? true else { throw DeviceWalletError.invalidProof }
            var local = try await vault.summary(accountID: accountID, registeredAddress: registered.address)
            try check(accountID, operation)
            if let address = registered.address, local?.address != address {
                state = .recoveryRequired(address: address)
                return
            }
            if local == nil {
                local = try await vault.create(accountID: accountID)
                try check(accountID, operation)
            }
            guard let local, local.accountID == accountID, TradingWalletChallenge.validAddress(local.address) else {
                throw DeviceWalletError.storage
            }
            if registered.address == nil { try await bind(local, operation: operation) }
            try check(accountID, operation)
            state = .verified(local)
        } catch { handle(error, operation: operation) }
    }

    func revealRecovery() async throws -> [String] {
        guard !isBusy, case .verified(let local) = state else { throw DeviceWalletError.locked }
        let operation = revision
        try check(local.accountID, operation)
        isBusy = true
        defer { isBusy = false }
        let words = try await vault.recoveryWords(accountID: local.accountID, address: local.address)
        try check(local.accountID, operation)
        return words
    }

    func confirmRecovery(phrase: String) async -> Bool {
        guard !isBusy, case .verified(let local) = state else { return false }
        let operation = revision
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try check(local.accountID, operation)
            let verified = try await vault.verifyRecovery(accountID: local.accountID, address: local.address, phrase: phrase)
            try check(local.accountID, operation)
            state = .verified(verified)
            return true
        } catch {
            if revision == operation { errorMessage = message(error) }
            return false
        }
    }

    func restore(phrase: String) async -> Bool {
        guard !isBusy, let accountID = service.walletAccountID,
              case .recoveryRequired(let expected) = state else { return false }
        let operation = revision
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let registered = try await service.walletRegistration()
            try check(accountID, operation)
            guard registered.accountId == accountID, registered.address == expected else { throw DeviceWalletError.invalidProof }
            let local = try await vault.restore(accountID: accountID, address: expected, phrase: phrase)
            try check(accountID, operation)
            try await bind(local, operation: operation)
            try check(accountID, operation)
            state = .verified(local)
            return true
        } catch {
            if revision == operation { errorMessage = message(error) }
            return false
        }
    }

    private func bind(_ local: DeviceWalletSummary, operation: UUID) async throws {
        let challenge = try await service.walletChallenge(address: local.address)
        try check(local.accountID, operation)
        _ = try challenge.message(accountID: local.accountID, address: local.address)
        let signature = try await vault.signBinding(accountID: local.accountID, challenge: challenge)
        try check(local.accountID, operation)
        let bound = try await service.bindWallet(challenge: challenge, signature: signature)
        guard bound.accountId == local.accountID, bound.address == local.address else { throw DeviceWalletError.invalidProof }
    }

    private func check(_ accountID: UUID, _ operation: UUID) throws {
        try Task.checkCancellation()
        guard revision == operation, service.walletAccountID == accountID else { throw DeviceWalletError.accountChanged }
    }

    private func handle(_ error: Error, operation: UUID) {
        guard revision == operation else { return }
        state = .locked
        errorMessage = message(error)
    }

    private func message(_ error: Error) -> String? {
        if error is CancellationError { return nil }
        if let error = error as? DeviceWalletError { return error.errorDescription }
        if let error = error as? AccountAccessError { return error.errorDescription }
        return "Wallet service is unavailable. Your existing wallet has not been replaced.".bSmartLocalized
    }
}
