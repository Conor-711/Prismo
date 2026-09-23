#if DEBUG
import Foundation

enum SocialChatPreviewData {
    static let messages: [SocialMessage] = {
        let alice = FeedPublicProfile(id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, nickname: "Alice", avatarURL: nil)
        let ben = FeedPublicProfile(id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!, nickname: "Ben", avatarURL: nil)
        let first = SocialMessage(id: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!, isMine: false,
            text: "What are you watching in the market today?", sentAt: Date().addingTimeInterval(-300), sender: alice)
        let second = SocialMessage(id: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!, isMine: false,
            text: "Reading the latest earnings and comparing them with the previous quarter before making a decision.",
            sentAt: Date().addingTimeInterval(-200), sender: ben,
            reply: .init(id: first.id, senderName: "Alice", text: first.text, hasImage: false))
        return [first, second, SocialMessage(id: UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!,
            isMine: true, text: "Same here", sentAt: Date().addingTimeInterval(-100))]
    }()
}
#endif
