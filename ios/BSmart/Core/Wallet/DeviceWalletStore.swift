import Foundation
import Combine

@MainActor
protocol AccountWalletServicing: AnyObject {
    var walletAccountID: UUID? { get }
    var walletSessionRevision: UUID { get }
    var walletSessionIsRefreshing: Bool { get }
    func walletRegistration() async throws -> TradingWalletRegistration
    func walletChallenge(address: String) async throws -> TradingWalletChallenge
    func bindWallet(challenge: TradingWalletChallenge, signature: String) async throws -> TradingWalletRegistration
    func fundingSigningLease(wallet: DeviceWalletSummary) throws -> FundingSigningLease
}

extension AccountWalletServicing {
    var walletSessionRevision: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000000")! }
    var walletSessionIsRefreshing: Bool { false }

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
    @Published private(set) var userPresenceRequired = true
    private let service: AccountWalletServicing
    private let vault: DeviceWalletVault
    let signing: any TradingWalletSigning
    private var revision = UUID()

    init(service: AccountWalletServicing, vault: DeviceWalletVault = KeychainDeviceWalletVault(),
         signing: any TradingWalletSigning = KeychainDeviceWalletVault()) {
        self.service = service
        self.vault = vault
        self.signing = signing
    }

    func lock() {
        revision = UUID()
        state = .locked
        userPresenceRequired = true
        WalletAuthenticationSession.shared.invalidate()
        errorMessage = nil
        // An in-flight vault write retains its account scope; don't allow overlapping writes.
    }

    func prepare(allowCreation: Bool = true) async {
        guard !isBusy, let accountID = service.walletAccountID else { return }
        if case .verified(let value) = state, value.accountID == accountID { return }
        let operation = revision
        let sessionRevision = service.walletSessionRevision
        isBusy = true
        state = .loading
        errorMessage = nil
        defer { isBusy = false }
        for attempt in 0..<2 {
            do {
                try await prepareWallet(accountID: accountID, operation: operation,
                                        sessionRevision: sessionRevision, allowCreation: allowCreation)
                return
            } catch DeviceWalletError.accountChanged {
                guard attempt == 0, !allowCreation, revision == operation,
                      service.walletSessionRevision == sessionRevision,
                      service.walletAccountID == accountID || service.walletSessionIsRefreshing else {
                    handle(DeviceWalletError.accountChanged, operation: operation)
                    return
                }
                do { try await waitForSameAccount(accountID, operation: operation, sessionRevision: sessionRevision) }
                catch { handle(error, operation: operation); return }
            } catch {
                handle(error, operation: operation)
                return
            }
        }
    }

    private func prepareWallet(accountID: UUID, operation: UUID, sessionRevision: UUID,
                               allowCreation: Bool) async throws {
        let registered = try await service.walletRegistration()
        try check(accountID, operation, sessionRevision: sessionRevision)
        guard registered.accountId == accountID,
              registered.address.map(TradingWalletChallenge.validAddress) ?? true else { throw DeviceWalletError.invalidProof }
        // Trade entry may reconnect an existing wallet, never create or bind one implicitly.
        guard allowCreation || registered.address != nil else { state = .locked; return }
        var local = try await vault.summary(accountID: accountID, registeredAddress: registered.address)
        try check(accountID, operation, sessionRevision: sessionRevision)
        if let address = registered.address, local?.address != address {
            state = .recoveryRequired(address: address)
            return
        }
        if local == nil {
            local = try await vault.create(accountID: accountID)
            try check(accountID, operation, sessionRevision: sessionRevision)
        }
        guard let local, local.accountID == accountID, TradingWalletChallenge.validAddress(local.address) else {
            throw DeviceWalletError.storage
        }
        if registered.address == nil { try await bind(local, operation: operation, sessionRevision: sessionRevision) }
        let requiresPresence = try await vault.userPresenceRequired(accountID: accountID, address: local.address)
        try check(accountID, operation, sessionRevision: sessionRevision)
        userPresenceRequired = requiresPresence
        state = .verified(local)
    }

    private func waitForSameAccount(_ accountID: UUID, operation: UUID, sessionRevision: UUID) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while service.walletAccountID != accountID {
            try Task.checkCancellation()
            guard revision == operation, service.walletSessionRevision == sessionRevision,
                  service.walletSessionIsRefreshing, ContinuousClock.now < deadline else {
                throw DeviceWalletError.accountChanged
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        try check(accountID, operation, sessionRevision: sessionRevision)
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

    func setUserPresenceRequired(_ required: Bool) async {
        guard !isBusy, case .verified(let wallet) = state else { return }
        let operation = revision
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do {
            try check(wallet.accountID, operation)
            try await vault.setUserPresenceRequired(required, accountID: wallet.accountID, address: wallet.address)
            try check(wallet.accountID, operation)
            userPresenceRequired = required
        } catch {
            if revision == operation { errorMessage = message(error) }
        }
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
        let sessionRevision = service.walletSessionRevision
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let registered = try await service.walletRegistration()
            try check(accountID, operation, sessionRevision: sessionRevision)
            guard registered.accountId == accountID, registered.address == expected else { throw DeviceWalletError.invalidProof }
            let local = try await vault.restore(accountID: accountID, address: expected, phrase: phrase)
            try check(accountID, operation, sessionRevision: sessionRevision)
            try await bind(local, operation: operation, sessionRevision: sessionRevision)
            let requiresPresence = try await vault.userPresenceRequired(accountID: accountID, address: local.address)
            try check(accountID, operation, sessionRevision: sessionRevision)
            userPresenceRequired = requiresPresence
            state = .verified(local)
            return true
        } catch {
            if revision == operation { errorMessage = message(error) }
            return false
        }
    }

    private func bind(_ local: DeviceWalletSummary, operation: UUID, sessionRevision: UUID) async throws {
        let challenge = try await service.walletChallenge(address: local.address)
        try check(local.accountID, operation, sessionRevision: sessionRevision)
        _ = try challenge.message(accountID: local.accountID, address: local.address)
        let signature = try await vault.signBinding(accountID: local.accountID, challenge: challenge)
        try check(local.accountID, operation, sessionRevision: sessionRevision)
        let bound = try await service.bindWallet(challenge: challenge, signature: signature)
        guard bound.accountId == local.accountID, bound.address == local.address else { throw DeviceWalletError.invalidProof }
    }

    private func check(_ accountID: UUID, _ operation: UUID, sessionRevision: UUID? = nil) throws {
        try Task.checkCancellation()
        guard revision == operation, service.walletAccountID == accountID,
              sessionRevision == nil || service.walletSessionRevision == sessionRevision else {
            throw DeviceWalletError.accountChanged
        }
    }

    private func handle(_ error: Error, operation: UUID) {
        guard revision == operation else { return }
        state = .locked
        errorMessage = message(error)
    }

    private func message(_ error: Error) -> String? {
        if error is CancellationError { return nil }
        if let error = error as? DeviceWalletError { return error.errorDescription }
        if let error = error as? EmbeddedWalletError { return error.errorDescription }
        if let error = error as? AccountAccessError { return error.errorDescription }
        return "Wallet service is unavailable. Your existing wallet has not been replaced.".bSmartLocalized
    }
}
