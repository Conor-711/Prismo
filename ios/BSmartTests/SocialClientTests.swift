import XCTest
@testable import BSmart

final class SocialClientTests: XCTestCase {
    func testSnapshotDecodesPublicProfilesAndUnreadMessages() throws {
        let data = Data(#"""
        {
          "following": [{"profile": {"id": "11111111-1111-4111-8111-111111111111",
            "nickname": "Alice", "handle": "alice", "avatarURL": null},
            "at": "2026-09-21T01:00:00+00:00"}],
          "followers": [],
          "conversations": [{"profile": {"id": "11111111-1111-4111-8111-111111111111",
            "nickname": "Alice", "handle": "alice", "avatarURL": null},
            "lastMessage": {"id": "22222222-2222-4222-8222-222222222222",
              "isMine": false, "text": "Hello", "sentAt": "2026-09-21T02:00:00.123456+00:00"},
            "unreadCount": 2}]
        }
        """#.utf8)
        let snapshot = try BSmartJSONCoding.makeDecoder().decode(SocialSnapshot.self, from: data)
        try snapshot.validate()
        XCTAssertEqual(snapshot.following.first?.profile.handle, "alice")
        XCTAssertEqual(snapshot.conversations.first?.unreadCount, 2)
        XCTAssertFalse(snapshot.conversations[0].lastMessage.isMine)
    }

    func testMessageCursorKeepsServerTimestampPrecision() throws {
        let data = Data(#"""
        {"items": [{"id": "22222222-2222-4222-8222-222222222222",
          "isMine": true, "text": "Hello", "sentAt": "2026-09-21T02:00:00.123456+00:00"}],
         "nextBeforeAt": "2026-09-21T02:00:00.123456+00:00",
         "nextBeforeID": "22222222-2222-4222-8222-222222222222"}
        """#.utf8)
        let page = try BSmartJSONCoding.makeDecoder().decode(SocialMessagesPage.self, from: data)
        try page.validate()
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextBeforeAt, "2026-09-21T02:00:00.123456+00:00")
    }
}
