import Combine
import Foundation

private struct GlobalChatMessageCursor: Codable, Comparable {
    let sentAt: Date
    let id: UUID

    init(_ message: SocialMessage) {
        sentAt = message.sentAt
        id = message.id
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.sentAt == rhs.sentAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.sentAt < rhs.sentAt
    }
}

private struct GlobalChatReadState: Codable, Equatable {
    var seeded = false
    var cursor: GlobalChatMessageCursor?
}

@MainActor
final class GlobalChatUnreadStore: ObservableObject {
    @Published private(set) var hasUnread = false
    @Published private(set) var latestMessage: SocialMessage?
    private(set) var isViewing = false

    private let defaults: UserDefaults
    private var accountID: UUID?
    private var readState = GlobalChatReadState()
    private var latestObserved: GlobalChatMessageCursor?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func activate(accountID: UUID?) {
        guard self.accountID != accountID else { return }
        self.accountID = accountID
        isViewing = false
        hasUnread = false
        latestObserved = nil
        latestMessage = nil
        readState = accountID.flatMap { id in
            defaults.data(forKey: key(for: id)).flatMap { try? JSONDecoder().decode(GlobalChatReadState.self, from: $0) }
        } ?? GlobalChatReadState()
    }

    func ingest(_ messages: [SocialMessage], accountID: UUID) {
        activate(accountID: accountID)
        updateLatestMessage(messages)
        let newest = messages.map(GlobalChatMessageCursor.init).max()
        latestObserved = [latestObserved, newest].compactMap { $0 }.max()

        if !readState.seeded {
            readState = GlobalChatReadState(seeded: true, cursor: newest)
            persist()
            return
        }
        if isViewing {
            markRead(messages)
        } else if messages.contains(where: { message in
            !message.isMine && (readState.cursor.map { GlobalChatMessageCursor(message) > $0 } ?? true)
        }) {
            hasUnread = true
        }
    }

    func beginViewing(accountID: UUID?) {
        if let accountID { activate(accountID: accountID) }
        isViewing = true
    }

    func endViewing() {
        isViewing = false
    }

    func markRead(_ messages: [SocialMessage]) {
        guard accountID != nil else {
            hasUnread = false
            return
        }
        updateLatestMessage(messages)
        let previous = readState
        let newest = messages.map(GlobalChatMessageCursor.init).max()
        latestObserved = [latestObserved, newest].compactMap { $0 }.max()
        readState.seeded = true
        readState.cursor = [readState.cursor, latestObserved].compactMap { $0 }.max()
        hasUnread = false
        if readState != previous { persist() }
    }

#if DEBUG
    func showFixtureUnread() {
        hasUnread = true
        updateLatestMessage(SocialChatPreviewData.messages)
    }
#endif

    private func persist() {
        guard let accountID, let data = try? JSONEncoder().encode(readState) else { return }
        defaults.set(data, forKey: key(for: accountID))
    }

    private func updateLatestMessage(_ messages: [SocialMessage]) {
        guard let newest = messages.max(by: { GlobalChatMessageCursor($0) < GlobalChatMessageCursor($1) }),
              latestMessage.map({ GlobalChatMessageCursor($0) < GlobalChatMessageCursor(newest) }) ?? true else { return }
        latestMessage = newest
    }

    private func key(for accountID: UUID) -> String {
        "bsmart.global-chat.read.\(accountID.uuidString)"
    }
}
