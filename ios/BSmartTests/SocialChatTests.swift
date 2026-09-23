import XCTest
import UIKit
@testable import BSmart

final class SocialChatTests: XCTestCase {
    @MainActor
    func testGlobalChatUnreadIgnoresOwnMessagesAndClearsWhenViewed() {
        let suite = "bsmart.global-chat-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let accountID = UUID()
        let store = GlobalChatUnreadStore(defaults: defaults)
        let original = SocialMessage(id: UUID(), isMine: false, text: "Old", sentAt: Date(timeIntervalSince1970: 1))
        let own = SocialMessage(id: UUID(), isMine: true, text: "Mine", sentAt: Date(timeIntervalSince1970: 2))
        let incoming = SocialMessage(id: UUID(), isMine: false, text: "New", sentAt: Date(timeIntervalSince1970: 3))
        let whileViewing = SocialMessage(id: UUID(), isMine: false, text: "Read live", sentAt: Date(timeIntervalSince1970: 4))

        store.ingest([original], accountID: accountID)
        XCTAssertFalse(store.hasUnread)
        XCTAssertEqual(store.latestMessage?.id, original.id)
        store.ingest([original, own], accountID: accountID)
        XCTAssertFalse(store.hasUnread)
        XCTAssertEqual(store.latestMessage?.id, own.id)
        store.ingest([original, own, incoming], accountID: accountID)
        XCTAssertTrue(store.hasUnread)
        XCTAssertEqual(store.latestMessage?.id, incoming.id)

        store.beginViewing(accountID: accountID)
        XCTAssertTrue(store.hasUnread)
        store.markRead([incoming])
        XCTAssertFalse(store.hasUnread)
        store.ingest([incoming, whileViewing], accountID: accountID)
        XCTAssertFalse(store.hasUnread)
        XCTAssertEqual(store.latestMessage?.id, whileViewing.id)
        store.markRead([original])
        XCTAssertEqual(store.latestMessage?.id, whileViewing.id)
        store.endViewing()

        let restored = GlobalChatUnreadStore(defaults: defaults)
        restored.ingest([incoming, whileViewing], accountID: accountID)
        XCTAssertFalse(restored.hasUnread)
        let later = SocialMessage(id: UUID(), isMine: false, text: "Later", sentAt: Date(timeIntervalSince1970: 5))
        restored.ingest([later], accountID: accountID)
        XCTAssertTrue(restored.hasUnread)
        restored.markRead([later])
        XCTAssertFalse(restored.hasUnread)
    }

    @MainActor
    func testGlobalChatUnreadSeedsEmptyRoomAndSeparatesAccounts() {
        let suite = "bsmart.global-chat-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let firstAccount = UUID(), secondAccount = UUID()
        let store = GlobalChatUnreadStore(defaults: defaults)
        store.ingest([], accountID: firstAccount)
        XCTAssertFalse(store.hasUnread)
        let message = SocialMessage(id: UUID(), isMine: false, text: "Hello", sentAt: Date(timeIntervalSince1970: 1))
        store.ingest([message], accountID: firstAccount)
        XCTAssertTrue(store.hasUnread)
        XCTAssertEqual(store.latestMessage?.id, message.id)
        store.activate(accountID: secondAccount)
        XCTAssertNil(store.latestMessage)
        store.ingest([message], accountID: secondAccount)
        XCTAssertFalse(store.hasUnread)
        store.activate(accountID: firstAccount)
        store.ingest([message], accountID: firstAccount)
        XCTAssertTrue(store.hasUnread)
    }

    func testRichMessageDecodesImageOnlyAndReply() throws {
        let json = #"""
        {"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","isMine":false,"text":"",
         "sentAt":"2026-09-22T10:00:00Z",
         "sender":{"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","nickname":"Alice"},
         "image":{"url":"https://example.com/image.jpg","width":1600,"height":900},
         "reply":{"id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","senderName":"Ben","text":"Hi","hasImage":false}}
        """#
        let message = try BSmartJSONCoding.makeDecoder().decode(SocialMessage.self, from: Data(json.utf8))
        XCTAssertTrue(message.isValid)
        XCTAssertEqual(message.sender?.nickname, "Alice")
        XCTAssertEqual(message.reply?.text, "Hi")
        XCTAssertEqual(message.image?.width, 1600)
    }

    func testInvalidImageAndEmptyDraftAreRejected() {
        XCTAssertFalse(SocialMessageImage(url: URL(string: "http://example.com/a")!, width: 30, height: 30).isValid)
        XCTAssertFalse(SocialMessageImage(url: URL(string: "https://example.com/a")!, width: 9000, height: 30).isValid)
        XCTAssertFalse(SocialChatDraft(id: UUID(), text: " ", replyToID: nil, imageBase64: nil).isValid)
        XCTAssertFalse(SocialChatDraft(id: UUID(), text: String(repeating: "a", count: 2001), replyToID: nil, imageBase64: nil).isValid)
    }

    func testSharedOpinionRoundTripsAsCardAndKeepsReadablePreview() throws {
        let shared = SocialSharedContent(kind: .opinion, id: UUID().uuidString.lowercased(),
            title: "Avery", detail: "#3 · Top 5%", summary: "A short summary", ticker: "XYZ:NVDA",
            publishedAt: "2026-09-22T10:00:00Z", avatarURL: URL(string: "https://example.com/avery.jpg"))
        XCTAssertTrue(shared.isValid)
        let draft = SocialChatDraft(id: UUID(), text: shared.preview, replyToID: nil,
                                    imageBase64: nil, share: shared)
        XCTAssertTrue(draft.isValid)
        let encoded = try JSONEncoder().encode(draft)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual((json["share"] as? [String: Any])?["kind"] as? String, "opinion")
        XCTAssertEqual((json["share"] as? [String: Any])?["avatarURL"] as? String,
                       "https://example.com/avery.jpg")
        let messageJSON = """
        {"id":"\(UUID().uuidString)","isMine":false,"text":"Shared opinion: NVDA",
         "sentAt":"2026-09-22T10:01:00Z","share":\(String(decoding: try JSONEncoder().encode(shared), as: UTF8.self))}
        """
        let message = try BSmartJSONCoding.makeDecoder().decode(SocialMessage.self, from: Data(messageJSON.utf8))
        XCTAssertTrue(message.isValid)
        XCTAssertEqual(message.share, shared)
        XCTAssertTrue(message.preview.contains("NVDA"))
        let invalid = SocialSharedContent(kind: .opinion, id: "bad", title: "Avery", detail: "", summary: nil,
                                          ticker: "NVDA", publishedAt: nil)
        XCTAssertFalse(invalid.isValid)
    }

    func testSharedCardAcceptsOlderPayloadAndRejectsUnsafeAvatarURL() throws {
        let legacy = #"{"kind":"investor","id":"author-1","title":"Avery","detail":"Top 5%"}"#
        let decoded = try JSONDecoder().decode(SocialSharedContent.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.avatarURL)
        XCTAssertTrue(decoded.isValid)
        let unsafe = SocialSharedContent(kind: .investor, id: "author-1", title: "Avery",
            detail: "Top 5%", summary: nil, ticker: "NVDA", publishedAt: nil,
            avatarURL: URL(string: "http://example.com/avery.jpg"))
        XCTAssertFalse(unsafe.isValid)
        XCTAssertNil(SocialSharedContent.shareableAvatarURL(unsafe.avatarURL))
    }

    func testSharedCardClipsUnicodeToServerLimits() {
        let title = SocialSharedContent.clipped(String(repeating: "😀", count: 100), utf16Limit: 100)
        XCTAssertEqual(title.utf16.count, 100)
        let shared = SocialSharedContent(kind: .ticker, id: "NVDA", title: title,
            detail: SocialSharedContent.clipped(String(repeating: "市场", count: 90), utf16Limit: 120),
            summary: SocialSharedContent.clipped(String(repeating: "中文摘要", count: 100), utf16Limit: 300),
            ticker: "NVDA", publishedAt: nil)
        XCTAssertTrue(shared.isValid)
        XCTAssertLessThanOrEqual(try! JSONEncoder().encode(shared).count, 4096)
    }

    func testMergeDeduplicatesPollingAndRetainsEarlierPages() {
        let first = SocialMessage(id: UUID(), isMine: false, text: "First", sentAt: Date(timeIntervalSince1970: 1))
        let second = SocialMessage(id: UUID(), isMine: true, text: "Second", sentAt: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(SocialMessageMerge.merge([first, second], [second]), [first, second])
        var refreshed = second
        refreshed.image = .init(url: URL(string: "https://example.com/new-signed-url")!, width: 30, height: 30)
        XCTAssertEqual(SocialMessageMerge.merge([first, second], [refreshed]), [first, refreshed])
        XCTAssertEqual(SocialMessageMerge.merge([first, second], [refreshed], refreshExisting: false), [first, second])
    }

    func testTransientPollingFailureDoesNotHideLoadedMessages() {
        var state = SocialChatRefreshState()
        XCTAssertFalse(state.failed(hasMessages: true))
        XCTAssertFalse(state.failed(hasMessages: true))
        state.succeeded()
        XCTAssertEqual(state.consecutiveFailures, 0)
        XCTAssertFalse(state.failed(hasMessages: true))
        XCTAssertFalse(state.failed(hasMessages: true))
        XCTAssertTrue(state.failed(hasMessages: true))
        state.succeeded()
        XCTAssertEqual(state.consecutiveFailures, 0)
    }

    func testEmptyChatShowsFailureAfterTwoAttempts() {
        var state = SocialChatRefreshState()
        XCTAssertFalse(state.failed(hasMessages: false))
        XCTAssertTrue(state.failed(hasMessages: false))
    }

    func testDraftKeepsIdempotencyAndReplyInEncodedRequest() throws {
        let id = UUID(), reply = UUID()
        let draft = SocialChatDraft(id: id, text: "Reply", replyToID: reply, imageBase64: nil)
        let data = try JSONEncoder().encode(draft)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json["id"], id.uuidString)
        XCTAssertEqual(json["replyToID"], reply.uuidString)
        XCTAssertEqual(try JSONEncoder().encode(draft).count, data.count)
    }

    func testPhotoPreparationLimitsDimensionsAndEmitsJPEG() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2200, height: 1000))
        let input = renderer.image { ctx in UIColor.systemGreen.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 2200, height: 1000)) }
        let photo = try PreparedChatPhoto.prepare(XCTUnwrap(input.pngData()))
        let jpeg = try XCTUnwrap(Data(base64Encoded: photo.base64))
        XCTAssertLessThanOrEqual(max(photo.preview.size.width, photo.preview.size.height), 1600)
        XCTAssertLessThanOrEqual(jpeg.count, 2_097_152)
        XCTAssertEqual(Array(jpeg.prefix(2)), [255, 216])
        XCTAssertThrowsError(try PreparedChatPhoto.prepare(Data("not an image".utf8)))
    }
}
