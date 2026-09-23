import Foundation
import PrivySDK

// One SDK instance for the app lifetime. Supabase, not Privy's OAuth UI, owns login.
@MainActor
final class PrivyEmbeddedWalletClient: EmbeddedWalletClient {
    private let configuration: PrivyWalletConfiguration?
    private let account: AccountAccessStore
    private var sdk: (any Privy)?
    private var operationAccountID: UUID?
    private var authenticatedAccountID: UUID?
    private var isBusy = false
    private var needsSessionCleanup = false
    private var stage = EmbeddedWalletFailure.Stage.configuration
    private var backoff = EmbeddedWalletBackoff()
    private var uncertainCreations = Set<UUID>()

    var isConfigured: Bool { configuration != nil }

    init(account: AccountAccessStore, configuration: PrivyWalletConfiguration? = .resolve()) {
        self.account = account
        self.configuration = configuration
    }

    // SDK operations are serialized so an account switch cannot share a token provider
    // with a signature or wallet creation belonging to the previous account.
    private func withUser<T>(accountID: UUID, operation: (any PrivyUser) async throws -> T) async throws -> T {
        guard let configuration else { throw EmbeddedWalletError.notConfigured }
        let revision = account.walletSessionRevision
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while isBusy {
            guard account.walletSessionRevision == revision, account.walletAccountID == accountID else {
                throw DeviceWalletError.accountChanged
            }
            guard ContinuousClock.now < deadline else { throw EmbeddedWalletError.busy }
            try await Task.sleep(for: .milliseconds(50))
        }
        let remaining = backoff.remaining()
        guard remaining == 0 else { throw EmbeddedWalletError.rateLimited(seconds: remaining) }
        isBusy = true
        operationAccountID = accountID
        stage = .configuration
        defer {
            isBusy = false; operationAccountID = nil
            if needsSessionCleanup { Task { await self.accountDidChange() } }
        }
        func checkAccount() throws {
            try Task.checkCancellation()
            guard account.walletSessionRevision == revision, account.walletAccountID == accountID else {
                throw DeviceWalletError.accountChanged
            }
        }
        do {
            _ = try await account.embeddedWalletAccessToken(expectedAccountID: accountID)
            try checkAccount()
            if sdk == nil {
                sdk = PrivySdk.initialize(config: .init(appId: configuration.appID, appClientId: configuration.clientID,
                    customAuthConfig: .init(tokenProvider: { [weak self] in
                        guard let self else { return nil }
                        return try await self.accessToken()
                    })))
            }
            guard let sdk else { throw EmbeddedWalletError.notConfigured }
            stage = .authentication
            if case .authenticated(let previous) = sdk.getAuthStateWithoutRefresh(),
               !Self.matches(previous, accountID: accountID) {
                authenticatedAccountID = nil
                await previous.logout()
                try checkAccount()
            }
            let state = await sdk.getAuthState()
            try checkAccount()
            var user: (any PrivyUser)?
            if case .authenticated(let current) = state {
                if Self.matches(current, accountID: accountID) { user = current }
                else { await current.logout() }
            }
            _ = try await account.embeddedWalletAccessToken(expectedAccountID: accountID)
            try checkAccount()
            if user == nil { user = try await sdk.customJwt.loginWithCustomAccessToken() }
            try checkAccount()
            guard let user, Self.matches(user, accountID: accountID) else { throw EmbeddedWalletError.identityMismatch }
            authenticatedAccountID = accountID
            _ = try await account.embeddedWalletAccessToken(expectedAccountID: accountID)
            try checkAccount()
            let result = try await operation(user)
            try checkAccount()
            backoff.succeeded()
            return result
        } catch let error as DeviceWalletError { throw error }
        catch let error as AccountAccessError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch {
            let failure = EmbeddedWalletFailure.map(error, stage: stage)
            if case .rateLimited = failure {
                throw EmbeddedWalletError.rateLimited(seconds: backoff.limited())
            }
            throw failure
        }
    }

    private func accessToken() async throws -> String? {
        guard let id = operationAccountID ?? authenticatedAccountID else { return nil }
        return try await account.embeddedWalletAccessToken(expectedAccountID: id)
    }

    private static func matches(_ user: any PrivyUser, accountID: UUID) -> Bool {
        user.linkedAccounts.contains {
            if case .customAuth(let identity) = $0 { return UUID(uuidString: identity.userId) == accountID }
            return false
        }
    }

    func resolve(accountID: UUID, address: String?, create: Bool) async throws -> DeviceWalletSummary? {
        try await withUser(accountID: accountID) { user in
            self.stage = .restoring
            let revision = self.account.walletSessionRevision
            let inventory = PrivyWalletInventory(user: user, refreshWallets: {
                try await user.refresh()
                self.uncertainCreations.remove(accountID)
            }) {
                guard self.account.walletAccountID == accountID, self.account.walletSessionRevision == revision else {
                    throw DeviceWalletError.accountChanged
                }
                self.stage = .creating
                self.uncertainCreations.insert(accountID)
                let wallet = try await user.createEthereumWallet(allowAdditional: false)
                self.uncertainCreations.remove(accountID)
                return wallet.address
            }
            guard let selected = try await EmbeddedWalletLookup.resolve(inventory, registeredAddress: address,
                create: create, reconcileCreation: self.uncertainCreations.contains(accountID)) else { return nil }
            guard TradingWalletChallenge.validAddress(selected) else {
                throw DeviceWalletError.invalidProof
            }
            self.uncertainCreations.remove(accountID)
            return .init(accountID: accountID, address: selected, recoveryVerified: false, provider: .privy)
        }
    }

    private func request(accountID: UUID, address: String, request: EthereumRpcRequest) async throws -> String {
        try await withUser(accountID: accountID) { user in
            self.stage = .signing
            guard let wallet = user.embeddedEthereumWallets.first(where: { $0.address.lowercased() == address }) else {
                throw EmbeddedWalletError.walletMismatch
            }
            return try await wallet.provider.request(request)
        }
    }

    func personalSign(accountID: UUID, address: String, message: String) async throws -> String {
        try await request(accountID: accountID, address: address, request: .personalSign(message: message, address: address))
    }

    func signTypedData(accountID: UUID, address: String, json: String) async throws -> String {
        try await request(accountID: accountID, address: address,
            request: .init(method: "eth_signTypedData_v4", params: [address, json]))
    }

    func signDigest(accountID: UUID, address: String, digest: Data) async throws -> String {
        guard digest.count == 32 else { throw DeviceWalletError.invalidProof }
        return try await request(accountID: accountID, address: address, request: .secp256k1Sign(hash: FundingHex.encode(digest)))
    }

    func accountDidChange() async {
        // A late logout must never clear a newly authenticated user's session.
        guard !isBusy else { needsSessionCleanup = true; return }
        needsSessionCleanup = false
        guard let sdk else { return }
        isBusy = true
        defer {
            isBusy = false
            if needsSessionCleanup { Task { await self.accountDidChange() } }
        }
        if case .authenticated(let user) = sdk.getAuthStateWithoutRefresh(),
           (account.identity?.id).map({ Self.matches(user, accountID: $0) }) != true {
            authenticatedAccountID = nil
            await user.logout()
        }
    }
}

@MainActor
private struct PrivyWalletInventory: EmbeddedWalletInventory {
    let user: any PrivyUser
    let refreshWallets: () async throws -> Void
    let createWallet: () async throws -> String
    var addresses: [String] { user.embeddedEthereumWallets.map(\.address) }
    func refresh() async throws { try await refreshWallets() }
    func create() async throws -> String { try await createWallet() }
}
