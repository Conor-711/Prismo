import Foundation
import Combine

@MainActor
final class AccountProfileStore: ObservableObject {
    @Published private(set) var profile: AccountProfile?
    @Published private(set) var accountID: UUID?
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    private var requestID = UUID()

    func acceptSaved(_ value: AccountProfile, for id: UUID) {
        guard accountID == id, profile?.id == value.id, value.isValid,
              value.revision > (profile?.revision ?? -1) else { return }
        requestID = UUID(); profile = value; loading = false; failed = false
    }

    func clear() {
        requestID = UUID(); profile = nil; accountID = nil; loading = false; failed = false
    }

    func load(account: AccountAccessStore) async {
        clear()
        guard let id = account.identity?.id else { return }
        let request = requestID
        accountID = id; loading = true
        do {
            let value = try await NativeAccountProfileClient(account: account).load(accountID: id)
            guard !Task.isCancelled, request == requestID, account.identity?.id == id else { return }
            profile = value; loading = false
        } catch {
            guard !Task.isCancelled, request == requestID, account.identity?.id == id else { return }
            failed = true; loading = false
        }
    }
}
