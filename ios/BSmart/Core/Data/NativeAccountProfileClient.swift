import Foundation

@MainActor
struct NativeAccountProfileClient {
    let account: AccountAccessStore
    var transport: SupabaseAccountTransport?

    init(account: AccountAccessStore, transport: SupabaseAccountTransport? = nil) {
        self.account = account
        self.transport = transport ?? SupabaseAccountConfiguration.resolve().map { SupabaseAccountTransport(configuration: $0) }
    }

    func load(accountID: UUID) async throws -> AccountProfile {
        try await request(accountID: accountID)
    }

    func save(_ profile: AccountProfile, avatar: AccountProfileAvatarInput, accountID: UUID) async throws -> AccountProfile {
        struct Input: Encodable {
            let username, handle, bio: String
            let revision: Int
            let avatar: AccountProfileAvatarInput
        }
        var draft = profile
        draft.username = draft.username.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.handle = AccountProfile.normalizedHandle(draft.handle)
        draft.bio = draft.bio.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft.isValid else { throw AccountProfileError.invalid }
        let body = try JSONEncoder().encode(Input(username: draft.username, handle: draft.handle, bio: draft.bio,
                                                  revision: draft.revision, avatar: avatar))
        let saved = try await request(accountID: accountID, body: body)
        guard saved.id == profile.id else { throw AccountAccessError.invalidResponse }
        account.feedSharingDidChange(accountID: accountID)
        return saved
    }

    private func request(accountID: UUID, body: Data? = nil) async throws -> AccountProfile {
        guard let transport else { throw AccountAccessError.unavailable }
        return try await account.withFeedSession(expectedAccountID: accountID) { token in
            let data = try await transport.request("functions/v1/bsmart-profile", method: body == nil ? "GET" : "PUT",
                                                   body: body, token: token)
            let profile = try BSmartJSONCoding.makeDecoder().decode(AccountProfile.self, from: data)
            guard profile.isValid else { throw AccountAccessError.invalidResponse }
            return profile
        }
    }
}
