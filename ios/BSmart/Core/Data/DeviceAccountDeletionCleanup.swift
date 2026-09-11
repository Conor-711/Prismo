import Foundation

@MainActor
final class DeviceAccountDeletionCleanup: AccountDeletionLocalCleanup {
    private let account: AccountAccessStore
    private let profiles: LocalUserProfileStore
    init(account: AccountAccessStore, profiles: LocalUserProfileStore? = nil) {
        self.account = account; self.profiles = profiles ?? LocalUserProfileStore()
    }
    func suspendAccount(_ identity: TradingAccountIdentity) throws {
        try account.suspendForAccountDeletion(identity)
    }
    func removeAccountData(_ identity: TradingAccountIdentity) async throws {
        try account.suspendForAccountDeletion(identity)
        try profiles.erase(accountID: identity.id)
        // Guest research preferences and all wallet/funding records are separate ownership domains.
    }
}
