import XCTest
@testable import BSmart

final class AccountProfileTests: XCTestCase {
    func testInitialSetupOnlyRequiresHandleAndDoesNotPublishProviderName() {
        let draft = AccountProfile(id: UUID(), username: "Provider Full Name", handle: " @Casey_01 ",
                                   bio: "", avatarURL: nil, revision: 0)
        let value = AccountProfileEditorDraft.submission(draft, onboarding: true)
        XCTAssertEqual(value.handle, "casey_01")
        XCTAssertEqual(value.username, "casey_01")
        XCTAssertEqual(value.bio, "")
        XCTAssertNil(value.avatarURL)
        XCTAssertTrue(value.isValid)
        XCTAssertTrue(value.needsSetup)
        XCTAssertEqual(value.id, draft.id)
    }

    func testInitialSetupStillRejectsEmptyOrInvalidHandles() {
        for handle in ["", "ab", "123", "two words"] {
            let draft = AccountProfile(id: UUID(), username: "", handle: handle, bio: "", avatarURL: nil, revision: 0)
            XCTAssertFalse(AccountProfileEditorDraft.submission(draft, onboarding: true).isValid)
        }
    }

    func testLaterEditingPreservesNicknameBioAndOptionalAvatar() {
        let draft = AccountProfile(id: UUID(), username: "Casey", handle: " @Casey_01 ", bio: "Investor",
                                   avatarURL: URL(string: "https://example.com/avatar.jpg"), revision: 2)
        for onboarding in [false, true] {
            let value = AccountProfileEditorDraft.submission(draft, onboarding: onboarding)
            XCTAssertEqual(value.username, draft.username)
            XCTAssertEqual(value.bio, draft.bio)
            XCTAssertEqual(value.avatarURL, draft.avatarURL)
            XCTAssertEqual(value.revision, 2)
            XCTAssertTrue(value.isValid)
        }
    }

    func testSetupCompletionUsesCloudRevisionNotLocalAvatarOrNickname() {
        let id = UUID()
        let initial = AccountProfile(id: id, username: "Google name", handle: "u_1234", bio: "",
                                     avatarURL: URL(string: "https://example.com/avatar.jpg"), revision: 0)
        let saved = AccountProfile(id: id, username: "Casey", handle: "casey", bio: "", avatarURL: nil, revision: 1)
        XCTAssertTrue(initial.needsSetup)
        XCTAssertFalse(saved.needsSetup)
        XCTAssertTrue(saved.isValid)
    }

    func testHandlesAreNormalizedButStrictAndUsernamesMayRepeat() {
        XCTAssertEqual(AccountProfile.normalizedHandle(" @Casey_01 "), "casey_01")
        for value in ["ab", "1casey", "Casey", "two words", "école", "casey\n", String(repeating: "a", count: 25)] {
            XCTAssertFalse(AccountProfile.validHandle(value), value)
        }
        let a = AccountProfile(id: UUID(), username: "Casey", handle: "casey_01", bio: "", avatarURL: nil, revision: 0)
        let b = AccountProfile(id: UUID(), username: "Casey", handle: "casey_02", bio: "Investor", avatarURL: nil, revision: 0)
        XCTAssertTrue(a.isValid && b.isValid)
    }

    func testFeedAndOpinionTradersDecodeCanonicalHandleWithLegacyCompatibility() throws {
        let id = UUID().uuidString
        let old = Data("{\"id\":\"\(id)\",\"nickname\":\"Casey\",\"avatarURL\":null}".utf8)
        let legacy = try JSONDecoder().decode(FeedPublicProfile.self, from: old)
        XCTAssertNil(legacy.handle)
        XCTAssertTrue(legacy.isValid)
        var profile = legacy; profile.handle = "casey_01"
        let roundTrip = try JSONDecoder().decode(FeedPublicProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(roundTrip.handle, "casey_01")
        profile.handle = "INVALID"; XCTAssertFalse(profile.isValid)
        let trader = OpinionTrader(id: UUID(), nickname: "Casey", avatarURL: nil, side: .long,
                                    tradedAt: Date(), handle: "casey_01")
        let decoded = try JSONDecoder().decode(OpinionTrader.self, from: JSONEncoder().encode(trader))
        XCTAssertEqual(decoded.handle, "casey_01")
    }

    func testAvatarRequestsNeverContainLocalPathOrUserControlledURL() throws {
        for action in [AccountProfileAvatarInput.keep, .remove, .provider] {
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(action)) as? [String: String])
            XCTAssertEqual(Set(json.keys), ["action"])
        }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with:
            JSONEncoder().encode(AccountProfileAvatarInput.upload(Data([1, 2, 3])))) as? [String: String])
        XCTAssertEqual(Set(json.keys), ["action", "jpegBase64"])
    }

    func testInvalidProfileBoundsAreRejected() {
        var value = AccountProfile(id: UUID(), username: "Casey", handle: "casey", bio: "", avatarURL: nil, revision: 0)
        value.bio = String(repeating: "x", count: 121); XCTAssertFalse(value.isValid)
        value.bio = ""; value.username = "  "; XCTAssertFalse(value.isValid)
    }
}
