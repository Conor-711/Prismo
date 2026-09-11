import Foundation
import Combine

@MainActor
final class AccountAccessStore: ObservableObject, AccountWalletServicing {
    @Published private(set) var configuration = AccountAuthConfiguration.unavailable
    @Published private(set) var identity: TradingAccountIdentity?
    @Published private(set) var isBusy = false
    @Published private(set) var didLoad = false
    @Published var errorMessage: String?
    private let client: AccountAuthenticating?
    private let storage: AccountSessionPersisting
    private let deletionStorage: AccountDeletionPersisting?
    private let renewal: AccountSessionRenewal?
    private let appleCredentials: AppleCredentialMonitor
    private let now: () -> Date
    private let continuousNow: @Sendable () -> ContinuousClock.Instant
    private var session: TradingAccountSession?
    private var fundingLease: FundingSigningLease?
    private var scope = UUID()
    private var isRenewing = false
    @Published private var providerChecks = 0
    private var providerValidation: (token: String, authorization: AppleCredentialAuthorization)?
    private var signingInProvider: AccountIdentityProvider?

    var supportsAccountDeletion: Bool { client is AccountDeleting }

    init(client: AccountAuthenticating?, storage: AccountSessionPersisting = KeychainAccountSessionStore(
        service: Bundle.main.bundleIdentifier ?? "today.bsmart.ios"
    ), deletionStorage: AccountDeletionPersisting? = nil,
         now: @escaping () -> Date = Date.init, appleCredentialState: AppleCredentialStateChecking? = nil,
         continuousNow: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.client = client
        self.storage = storage
        self.deletionStorage = deletionStorage
        self.renewal = client.map { AccountSessionRenewal(client: $0, storage: storage) }
        self.now = now
        self.continuousNow = continuousNow
        self.appleCredentials = AppleCredentialMonitor(client: appleCredentialState ?? NativeAppleCredentialStateClient(),
                                                       now: now, continuousNow: continuousNow)
    }

    func load() async {
        guard !isBusy, !isRenewing, providerChecks == 0 else { return }
        revokeFundingLease()
        clearTradingCapabilities()
        appleCredentials.invalidate()
        providerValidation = nil
        isBusy = true
        defer { isBusy = false; didLoad = true }
        identity = nil
        session = nil
        guard let client else { return }
        do {
            configuration = try await client.configuration()
            guard !configuration.providers.isEmpty else { return }
            try requireNoPendingDeletion()
            if let saved = try storage.load() {
                if try storage.isRenewalPending() {
                    try? await client.revoke(session: saved)
                    try storage.clear()
                    throw AccountAccessError.expired
                }
                guard saved.expiresAt > now() || (saved.refreshExpiresAt ?? .distantPast) > now() else {
                    try storage.clear(); return
                }
                session = saved
                try await validateAppleCredential(saved)
                try await renewIfNeeded()
                guard let candidate = session else { throw AccountAccessError.expired }
                let current = try await accountRequest(session: candidate) {
                    try await client.account(token: candidate.accessToken, provider: candidate.account.provider)
                }
                try Task.checkCancellation()
                guard session?.hasSameCredentials(as: candidate) == true else { throw CancellationError() }
                try requireNoPendingDeletion()
                guard current == candidate.account else { throw AccountAccessError.invalidResponse }
                identity = current
            }
        } catch {
            identity = nil
            session = nil
            if !Task.isCancelled {
                errorMessage = (error as? AccountAccessError)?.localizedDescription
                    ?? "Account service is unavailable. Please try again.".bSmartLocalized
            }
        }
    }

    func signIn(_ provider: AccountIdentityProvider,
                authorize: (AccountAuthChallenge) async throws -> AccountIdentityAssertion) async {
        guard !isBusy else { return }
        do { try requireNoPendingDeletion() }
        catch { errorMessage = AccountAccessError.storage.localizedDescription; return }
        revokeFundingLease()
        invalidateRenewal()
        guard let client, configuration.providers.contains(provider) else {
            errorMessage = AccountAccessError.unavailable.localizedDescription
            return
        }
        isBusy = true
        signingInProvider = provider
        let loginScope = scope
        errorMessage = nil
        defer { isBusy = false; signingInProvider = nil }
        do {
            try Task.checkCancellation()
            let challenge = try await client.challenge(provider: provider)
            try Task.checkCancellation()
            guard challenge.expiresAt > Date(), challenge.nonce.count >= 32 else { throw AccountAccessError.invalidResponse }
            let assertion = try await authorize(challenge)
            try Task.checkCancellation()
            try assertion.validate(for: provider)
            guard challenge.expiresAt > Date() else { throw AccountAccessError.expired }
            let verified = try await client.signIn(provider: provider, challenge: challenge.id, assertion: assertion)
            if Task.isCancelled {
                // A provider/code exchange may already have finished remotely; never publish its late result.
                let cleanup = Task { try? await client.signOut(token: verified.accessToken) }
                await cleanup.value
                throw CancellationError()
            }
            do {
                guard loginScope == scope else { throw CancellationError() }
                guard verified.account.provider == provider else { throw AccountAccessError.invalidResponse }
                try verified.validateReceipt()
                let appleAuthorization = provider == .apple ? try await appleCredentials.authorize(userID: assertion.appleUserID) : nil
                try Task.checkCancellation()
                guard loginScope == scope else { throw CancellationError() }
                try requireNoPendingDeletion()
                do { try storage.save(verified, appleUserID: assertion.appleUserID) } catch { throw AccountAccessError.storage }
                providerValidation = appleAuthorization.map { (verified.accessToken, $0) }
            } catch {
                if verified.hasValidAccessToken {
                    let cleanup = Task { try? await client.signOut(token: verified.accessToken) }
                    await cleanup.value
                }
                throw error
            }
            session = verified
            identity = verified.account
        } catch AccountAccessError.cancelled {
        } catch is CancellationError {
        } catch {
            if Task.isCancelled { return }
            errorMessage = (error as? AccountAccessError)?.localizedDescription
                ?? "Sign-in could not be verified. Please try again.".bSmartLocalized
        }
    }

    func signOut() async {
        guard !isBusy else { return }
        clearTradingCapabilities()
        revokeFundingLease()
        invalidateRenewal()
        isBusy = true
        defer { isBusy = false }
        do {
            if let saved = try storage.load() ?? session, saved.authority == .supabase {
                // Local logout must work offline. Keep wallet keys, but immediately remove signing access.
                try storage.clear()
                session = nil
                identity = nil
                if let client {
                    do { try await client.revoke(session: saved) }
                    catch AccountAccessError.expired {}
                    catch {
                        errorMessage = "Signed out on this device. The remote session could not be revoked.".bSmartLocalized
                    }
                }
                return
            }
            if let saved = try storage.load() ?? session, let client {
                if let refresh = saved.refreshToken {
                    try await client.revokeRefresh(token: refresh)
                } else {
                    do { try await client.signOut(token: saved.accessToken) }
                    catch AccountAccessError.expired { /* Legacy access-only session. */ }
                }
            }
            try storage.clear()
            session = nil
            identity = nil
        } catch {
            errorMessage = "Sign-out could not be completed. Please try again.".bSmartLocalized
        }
    }

    var walletAccountID: UUID? { try? walletSession().account.id }

    func fundingSigningLease(wallet: DeviceWalletSummary) throws -> FundingSigningLease {
        let active = try walletSession()
        guard wallet.accountID == active.account.id, wallet.canAuthorizeTransactions,
              TradingWalletChallenge.validAddress(wallet.address) else { throw DeviceWalletError.accountChanged }
        revokeFundingLease()
        let authorization = active.account.provider == .apple ? providerValidation?.authorization : nil
        let deadline = min(active.expiresAt, authorization?.expiresAt ?? active.expiresAt)
        let lease = FundingSigningLease(wallet: wallet, expiresAt: deadline,
                                       continuousDeadline: authorization?.deadline, continuousNow: continuousNow)
        fundingLease = lease
        return lease
    }

    private func revokeFundingLease() {
        fundingLease?.invalidate()
        fundingLease = nil
    }

    func walletRegistration() async throws -> TradingWalletRegistration {
        let active = try await validatedWalletSession()
        guard let client else { throw AccountAccessError.unavailable }
        do {
            let result = try await accountRequest(session: active) {
                try await client.wallet(token: active.accessToken)
            }
            guard try walletSession().accessToken == active.accessToken, result.accountId == active.account.id,
                  result.address.map(TradingWalletChallenge.validAddress) ?? true else { throw DeviceWalletError.accountChanged }
            applyTradingCapabilities(result, session: active)
            return result
        } catch {
            if session?.hasSameCredentials(as: active) == true { clearTradingCapabilities() }
            throw error
        }
    }

    func walletChallenge(address: String) async throws -> TradingWalletChallenge {
        let active = try await validatedWalletSession()
        guard let client else { throw AccountAccessError.unavailable }
        let result = try await accountRequest(session: active) {
            try await client.walletChallenge(address: address, token: active.accessToken)
        }
        guard try walletSession().accessToken == active.accessToken else { throw DeviceWalletError.accountChanged }
        _ = try result.message(accountID: active.account.id, address: address)
        return result
    }

    func bindWallet(challenge: TradingWalletChallenge, signature: String) async throws -> TradingWalletRegistration {
        let active = try await validatedWalletSession(allowRenewal: false)
        guard let client, active.account.id == challenge.accountId else { throw DeviceWalletError.accountChanged }
        _ = try challenge.message(accountID: active.account.id, address: challenge.address)
        let result = try await accountRequest(session: active) {
            try await client.bindWallet(challenge: challenge.id, signature: signature, token: active.accessToken)
        }
        guard try walletSession().accessToken == active.accessToken, result.accountId == active.account.id,
              result.address == challenge.address else { throw DeviceWalletError.invalidProof }
        applyTradingCapabilities(result, session: active)
        return result
    }

    private func applyTradingCapabilities(_ registration: TradingWalletRegistration, session: TradingAccountSession) {
        guard session.authority == .supabase else { return }
        let flags = registration.address == nil ? nil : registration.capabilities
        configuration = .init(providers: configuration.providers,
            depositsEnabled: flags?.depositsEnabled == true, tradingEnabled: flags?.tradingEnabled == true,
            withdrawalsEnabled: flags?.withdrawalsEnabled == true)
    }

    private func clearTradingCapabilities() {
        configuration = .init(providers: configuration.providers, depositsEnabled: false,
                              tradingEnabled: false, withdrawalsEnabled: false)
    }

    func maintainSession() async {
        // Revalidate on every foreground entry, including a previously cancelled restore.
        await load()
        while !Task.isCancelled {
            if !isBusy, !isRenewing, providerChecks == 0, session != nil {
                do { _ = try await validatedWalletSession() }
                catch {
                    if !Task.isCancelled { errorMessage = (error as? AccountAccessError)?.localizedDescription }
                }
            }
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
        }
    }

    private func renewIfNeeded() async throws {
        guard let active = session else { throw AccountAccessError.expired }
        if active.expiresAt.timeIntervalSince(now()) > 60 { return }
        if active.refreshToken == nil, active.expiresAt > now() { return }
        guard let renewal else { throw AccountAccessError.unavailable }
        let scope = self.scope
        revokeFundingLease()
        isRenewing = true
        defer { isRenewing = false }
        do {
            let renewed = try await renewal.renew(active)
            guard scope == self.scope else { throw CancellationError() }
            guard session?.accessToken == active.accessToken || session?.accessToken == renewed.accessToken else {
                throw DeviceWalletError.accountChanged
            }
            session = renewed
            if hasCurrentAppleAuthorization(for: active), let authorization = providerValidation?.authorization {
                providerValidation = (renewed.accessToken, authorization)
            }
            try await validateAppleCredential(renewed)
            if !isBusy { identity = renewed.account }
        } catch {
            if scope == self.scope { session = nil; identity = nil }
            throw error
        }
    }

    private func invalidateRenewal() {
        scope = UUID()
        renewal?.cancel()
        appleCredentials.invalidate()
        providerValidation = nil
    }

    func appleCredentialDidChange() {
        guard session?.account.provider == .apple || signingInProvider == .apple else { return }
        revokeFundingLease()
        invalidateRenewal()
    }

    func recheckAppleCredential() async {
        guard !isBusy, !isRenewing, session?.account.provider == .apple else { return }
        do { _ = try await validatedWalletSession() }
        catch {
            if !Task.isCancelled { errorMessage = (error as? AccountAccessError)?.localizedDescription }
        }
    }

    private func validatedWalletSession(allowRenewal: Bool = true) async throws -> TradingAccountSession {
        guard !isBusy, let active = session else { throw AccountAccessError.expired }
        try await validateAppleCredential(active)
        if allowRenewal { try await renewIfNeeded() }
        return try walletSession()
    }

    private func validateAppleCredential(_ active: TradingAccountSession) async throws {
        guard active.account.provider == .apple else { return }
        if hasCurrentAppleAuthorization(for: active) { return }
        revokeFundingLease()
        providerValidation = nil
        providerChecks += 1
        defer { providerChecks -= 1 }
        let scope = self.scope
        do {
            let authorization = try await appleCredentials.authorize(userID: storage.appleUserID(for: active))
            try Task.checkCancellation()
            guard scope == self.scope, session?.accessToken == active.accessToken else { throw CancellationError() }
            providerValidation = (active.accessToken, authorization)
            if errorMessage == AccountAccessError.credentialUnavailable.localizedDescription { errorMessage = nil }
        } catch AccountAccessError.expired {
            if scope == self.scope, session?.accessToken == active.accessToken {
                var persistenceError: Error?
                do { try clearRejectedSession(active) } catch { persistenceError = error }
                if let client {
                    let cleanup = Task {
                        try? await client.revoke(session: active)
                    }
                    await cleanup.value
                }
                if let persistenceError { throw persistenceError }
            }
            throw AccountAccessError.expired
        }
    }

    @discardableResult
    private func clearRejectedSession(_ active: TradingAccountSession) throws -> Bool {
        guard session?.accessToken == active.accessToken else { return false }
        revokeFundingLease()
        clearTradingCapabilities()
        invalidateRenewal()
        session = nil
        identity = nil
        errorMessage = AccountAccessError.expired.localizedDescription
        do { try storage.clear() }
        catch {
            errorMessage = AccountAccessError.storage.localizedDescription
            throw AccountAccessError.storage
        }
        return true
    }

    private func accountRequest<Value>(session active: TradingAccountSession,
                                       operation: () async throws -> Value) async throws -> Value {
        do {
            return try await operation()
        } catch AccountAccessError.expired {
            // A late 401 belongs to the credential sent, not to a subsequent login.
            try clearRejectedSession(active)
            throw AccountAccessError.expired
        }
    }

    private func walletSession() throws -> TradingAccountSession {
        try requireNoPendingDeletion()
        guard !isBusy, !isRenewing, providerChecks == 0, let session, identity == session.account,
              session.expiresAt > now() else { throw AccountAccessError.expired }
        if session.account.provider == .apple {
            guard hasCurrentAppleAuthorization(for: session) else { throw AccountAccessError.credentialUnavailable }
        }
        return session
    }

    private func hasCurrentAppleAuthorization(for session: TradingAccountSession) -> Bool {
        guard let validation = providerValidation, validation.token == session.accessToken else { return false }
        return validation.authorization.isValid(now: now(), instant: continuousNow())
    }

    private func requireNoPendingDeletion() throws {
        do {
            guard try deletionStorage?.load() == nil else { throw AccountDeletionError.unavailable }
        } catch {
            revokeFundingLease()
            throw error
        }
    }

    func suspendForAccountDeletion(_ expected: TradingAccountIdentity) throws {
        // Invalidate previously issued permissions even when protected storage is unreadable.
        revokeFundingLease()
        invalidateRenewal()
        guard identity == nil || identity == expected else { throw AccountDeletionError.accountChanged }
        session = nil; identity = nil
        let saved = try storage.load()
        guard saved == nil || saved?.account == expected else {
            throw AccountDeletionError.accountChanged
        }
        try storage.clear()
    }

    func reauthenticateForDeletion(expected: TradingAccountIdentity,
                                  authorize: (AccountAuthChallenge) async throws -> AccountIdentityAssertion) async throws
        -> (session: TradingAccountSession, googleUserID: String?) {
        guard !isBusy, !isRenewing, let client else { throw AccountDeletionError.unavailable }
        let pending = try deletionStorage?.load()
        guard (pending == nil && identity == expected)
                || (pending?.account == expected && pending?.stage == .submitted) else {
            throw AccountDeletionError.accountChanged
        }
        revokeFundingLease(); invalidateRenewal()
        let expectedScope = scope
        isBusy = true
        defer { isBusy = false }
        let result: (session: TradingAccountSession, googleUserID: String?)
        do {
            result = try await AccountDeletionReauthentication(client: client).authorize(expected: expected, authorize: authorize)
        } catch {
            // An exchange may commit before its response is lost. The old family is no longer trustworthy.
            if scope == expectedScope { try? suspendForAccountDeletion(expected) }
            throw error
        }
        do {
            try Task.checkCancellation()
            guard scope == expectedScope else { throw CancellationError() }
            // Fresh authentication replaces the old server family. Never keep its local signing access alive.
            try suspendForAccountDeletion(expected)
            return result
        } catch {
            await revokeTemporaryDeletionSession(result.session)
            throw error
        }
    }

    func revokeTemporaryDeletionSession(_ temporary: TradingAccountSession) async {
        guard let client else { return }
        let cleanup = Task {
            try? await client.revoke(session: temporary)
        }
        await cleanup.value
    }
}
