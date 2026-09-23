import Foundation

struct SocialMessage: Decodable, Identifiable, Hashable {
    let id: UUID
    let isMine: Bool
    let text: String
    let sentAt: Date

    var sender: FeedPublicProfile? = nil
    var image: SocialMessageImage? = nil
    var reply: SocialMessageReply? = nil
    var share: SocialSharedContent? = nil

    var preview: String { share?.preview ?? (text.isEmpty ? "Photo".bSmartLocalized : text) }
    var isValid: Bool {
        (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || image != nil || share != nil)
            && text.unicodeScalars.count <= 2000 && (sender == nil || sender?.isValid == true)
            && (image == nil || image?.isValid == true) && (reply == nil || reply?.isValid == true)
            && (share == nil || share?.isValid == true)
    }
}

struct SocialPerson: Decodable, Identifiable, Hashable {
    let profile: FeedPublicProfile
    let at: Date
    var id: UUID { profile.id }
}

struct SocialConversation: Decodable, Identifiable {
    let profile: FeedPublicProfile
    let lastMessage: SocialMessage
    let unreadCount: Int
    var id: UUID { profile.id }
}

struct SocialSnapshot: Decodable {
    let following: [SocialPerson]
    let followers: [SocialPerson]
    let conversations: [SocialConversation]

    static let empty = Self(following: [], followers: [], conversations: [])

    func validate() throws {
        guard following.count <= 10000, followers.count <= 10000, conversations.count <= 10000,
              following.allSatisfy({ $0.profile.isValid }), followers.allSatisfy({ $0.profile.isValid }),
              conversations.allSatisfy({ $0.profile.isValid && $0.lastMessage.isValid && $0.unreadCount >= 0 }),
              Set(following.map(\.id)).count == following.count,
              Set(followers.map(\.id)).count == followers.count,
              Set(conversations.map(\.id)).count == conversations.count else { throw BSmartAPIError.invalidResponse }
    }
}

struct SocialPeoplePage: Decodable {
    let people: [FeedPublicProfile]
    func validate() throws {
        guard people.count <= 20, people.allSatisfy(\.isValid),
              Set(people.map(\.id)).count == people.count else { throw BSmartAPIError.invalidResponse }
    }
}

struct SocialMessagesPage: Decodable {
    let items: [SocialMessage]
    let nextBeforeAt: String?
    let nextBeforeID: UUID?

    var hasMore: Bool { nextBeforeAt != nil && nextBeforeID != nil }

    func validate() throws {
        guard items.count <= 50, items.allSatisfy(\.isValid),
              Set(items.map(\.id)).count == items.count,
              (nextBeforeAt == nil) == (nextBeforeID == nil),
              !hasMore || !items.isEmpty else { throw BSmartAPIError.invalidResponse }
    }
}

@MainActor
struct NativeSocialClient {
    let account: AccountAccessStore
    var transport: SupabaseAccountTransport?

    init(account: AccountAccessStore, transport: SupabaseAccountTransport? = nil) {
        self.account = account
        self.transport = transport ?? SupabaseAccountConfiguration.resolve().map { SupabaseAccountTransport(configuration: $0) }
    }

    private func request<T: Decodable>(_ path: String = "", method: String = "GET",
                                       query: [URLQueryItem] = [], body: Data? = nil,
                                       accountID: UUID) async throws -> T {
        guard let transport else { throw AccountAccessError.unavailable }
        return try await account.withFeedSession(expectedAccountID: accountID) { token in
            let data = try await transport.request("functions/v1/bsmart-social" + path,
                method: method, query: query, body: body, token: token)
            return try BSmartJSONCoding.makeDecoder().decode(T.self, from: data)
        }
    }

    func snapshot(accountID: UUID) async throws -> SocialSnapshot {
        let value: SocialSnapshot = try await request(accountID: accountID)
        try value.validate()
        return value
    }

    func people(query: String, accountID: UUID) async throws -> [FeedPublicProfile] {
        let result: SocialPeoplePage = try await request("/people", query: [.init(name: "q", value: query)], accountID: accountID)
        try result.validate()
        return result.people
    }

    func follow(_ peerID: UUID, enabled: Bool, accountID: UUID) async throws -> SocialSnapshot {
        let body = try JSONEncoder().encode(["follow": enabled])
        let value: SocialSnapshot = try await request("/follows/\(peerID.uuidString)", method: "POST",
                                                       body: body, accountID: accountID)
        try value.validate()
        return value
    }

    func messages(_ peerID: UUID, before: SocialMessagesPage? = nil, accountID: UUID) async throws -> SocialMessagesPage {
        var query: [URLQueryItem] = []
        if let at = before?.nextBeforeAt, let id = before?.nextBeforeID {
            query = [.init(name: "beforeAt", value: at), .init(name: "beforeID", value: id.uuidString)]
        }
        let value: SocialMessagesPage = try await request("/messages/\(peerID.uuidString)", query: query, accountID: accountID)
        try value.validate()
        return value
    }

    func send(_ text: String, to peerID: UUID, accountID: UUID) async throws -> SocialMessage {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 2000 else { throw BSmartAPIError.invalidResponse }
        let body = try JSONEncoder().encode(["text": value])
        let message: SocialMessage = try await request("/messages/\(peerID.uuidString)", method: "POST",
                                                        body: body, accountID: accountID)
        guard message.isValid, message.isMine else { throw BSmartAPIError.invalidResponse }
        return message
    }

    func chat(_ room: SocialChatRoom, before: SocialMessagesPage? = nil, accountID: UUID) async throws -> SocialMessagesPage {
        var query: [URLQueryItem] = []
        if let at = before?.nextBeforeAt, let id = before?.nextBeforeID {
            query = [.init(name: "beforeAt", value: at), .init(name: "beforeID", value: id.uuidString)]
        }
        let page: SocialMessagesPage = try await request("/chat/\(room.id)", query: query, accountID: accountID)
        try page.validate()
        return page
    }

    func send(_ draft: SocialChatDraft, room: SocialChatRoom, accountID: UUID) async throws -> SocialMessage {
        guard draft.isValid else { throw AccountAccessError.invalidResponse }
        let result: SocialMessage = try await request("/chat/\(room.id)", method: "POST",
            body: JSONEncoder().encode(draft), accountID: accountID)
        guard result.isValid, result.isMine, result.id == draft.id else { throw AccountAccessError.invalidResponse }
        return result
    }
}
