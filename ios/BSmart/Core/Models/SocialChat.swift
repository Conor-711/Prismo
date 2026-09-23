import Foundation

enum SocialChatRoom: Identifiable, Hashable {
    case global
    case direct(FeedPublicProfile)
    var id: String {
        switch self { case .global: return "global"; case .direct(let peer): return peer.id.uuidString }
    }
    var title: String {
        switch self { case .global: return "Global Chat".bSmartLocalized; case .direct(let peer): return peer.nickname }
    }
    var peer: FeedPublicProfile? { if case .direct(let peer) = self { return peer }; return nil }
}

struct SocialMessageImage: Decodable, Hashable, Identifiable {
    let url: URL
    let width: Int
    let height: Int
    var id: URL { url }
    var isValid: Bool { url.scheme == "https" && (1...2048).contains(width) && (1...2048).contains(height) }
}

struct SocialMessageReply: Decodable, Hashable {
    let id: UUID
    let senderName: String
    let text: String
    let hasImage: Bool
    var isValid: Bool { !senderName.isEmpty && senderName.count <= 28 && text.count <= 240 }
    var preview: String { text.isEmpty && hasImage ? "Photo".bSmartLocalized : text }
}

struct SocialSharedContent: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case opinion, investor, ticker }
    let kind: Kind
    let id: String
    let title: String
    let detail: String
    let summary: String?
    let ticker: String?
    let publishedAt: String?
    var avatarURL: URL?

    init(kind: Kind, id: String, title: String, detail: String, summary: String?,
         ticker: String?, publishedAt: String?) {
        self.kind = kind
        self.id = id
        self.title = title
        self.detail = detail
        self.summary = summary
        self.ticker = ticker
        self.publishedAt = publishedAt
        self.avatarURL = nil
    }

    init(kind: Kind, id: String, title: String, detail: String, summary: String?,
         ticker: String?, publishedAt: String?, avatarURL: URL?) {
        self.init(kind: kind, id: id, title: title, detail: detail, summary: summary,
                  ticker: ticker, publishedAt: publishedAt)
        self.avatarURL = avatarURL
    }

    static func shareableAvatarURL(_ url: URL?) -> URL? {
        guard let url, url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil, url.absoluteString.utf16.count <= 1024 else { return nil }
        return url
    }

    static func clipped(_ value: String, utf16Limit: Int) -> String {
        var remaining = utf16Limit
        return String(value.prefix { character in
            let length = String(character).utf16.count
            guard length <= remaining else { return false }
            remaining -= length
            return true
        })
    }

    var isValid: Bool {
        (1...128).contains(id.utf16.count) && (1...100).contains(title.utf16.count) && detail.utf16.count <= 120
            && (summary == nil || summary!.utf16.count <= 300)
            && (ticker == nil || ticker!.range(of: "^[A-Z0-9:._-]{1,64}$", options: .regularExpression) != nil)
            && (publishedAt == nil || ISO8601DateFormatter().date(from: publishedAt!) != nil)
            && (avatarURL == nil || Self.shareableAvatarURL(avatarURL) != nil)
            && (kind != .opinion || UUID(uuidString: id) != nil && ticker != nil && publishedAt != nil)
            && (try? JSONEncoder().encode(self).count).map { $0 <= 4096 } == true
    }

    var preview: String {
        switch kind {
        case .opinion: return "Shared opinion".bSmartLocalized + ": " + (ticker ?? title)
        case .investor: return "Shared investor".bSmartLocalized + ": " + title
        case .ticker: return "Shared ticker".bSmartLocalized + ": " + title
        }
    }
}

struct SocialChatDraft: Encodable {
    let id: UUID
    let text: String
    let replyToID: UUID?
    let imageBase64: String?
    var share: SocialSharedContent? = nil
    var isValid: Bool {
        text.unicodeScalars.count <= 2000 && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || imageBase64 != nil || share != nil)
            && (imageBase64 == nil || (imageBase64!.count <= 2_796_204 && !imageBase64!.isEmpty))
            && (share == nil || share!.isValid)
    }
}

enum SocialMessageMerge {
    static func merge(_ current: [SocialMessage], _ incoming: [SocialMessage], refreshExisting: Bool = true) -> [SocialMessage] {
        var byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for message in incoming where refreshExisting || byID[message.id] == nil { byID[message.id] = message }
        return byID.values.sorted { $0.sentAt == $1.sentAt ? $0.id.uuidString < $1.id.uuidString : $0.sentAt < $1.sentAt }
    }
}

struct SocialChatRefreshState {
    private(set) var consecutiveFailures = 0

    mutating func succeeded() { consecutiveFailures = 0 }

    mutating func failed(hasMessages: Bool) -> Bool {
        consecutiveFailures += 1
        return consecutiveFailures >= (hasMessages ? 3 : 2)
    }
}

enum SocialChatError: Error {
    case rateLimited
    case invalidMessage
}
