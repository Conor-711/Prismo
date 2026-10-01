import XCTest
@testable import BSmart

final class NativeBaseQuotePresentationTests: XCTestCase {
    func testQuotePreviewRemovesBlankAndTrailingLinesWithoutChangingOriginal() {
        let original = "Crowdstrike (CRWD)\r\nhas all the trademarks\r\n \r\nof a pump and dump\n\n"
        XCTAssertEqual(NativeBaseQuotePresentation.preview(original),
                       "Crowdstrike (CRWD) has all the trademarks of a pump and dump")
        XCTAssertEqual(original.suffix(2), "\n\n")
        XCTAssertEqual(NativeBaseQuotePresentation.preview("\n \n"), "")
    }

    func testRedditQuoteUsesMatchingAuthorAvatarButNeverAnotherIdentity() throws {
        let base = try makeBase()
        var update = try XCTUnwrap(base.linkedUpdate)
        let image = URL(string: "https://i.redd.it/verified-avatar.png")!
        update.authorAvatarURL = image
        XCTAssertEqual(NativeBaseQuotePresentation.avatar(base: base, update: update, profile: nil), image)
        let otherBase = try makeBase(authorID: "reddit:another-user")
        XCTAssertNil(NativeBaseQuotePresentation.avatar(base: otherBase, update: update, profile: nil))
    }

    func testProfileAvatarRequiresExactAuthorAndPlatformNotNickname() throws {
        let base = try makeBase(), update = try XCTUnwrap(base.linkedUpdate)
        let profile = makeProfile()
        XCTAssertEqual(NativeBaseQuotePresentation.avatar(base: base, update: update, profile: profile), profile.avatarURL)
        XCTAssertNil(NativeBaseQuotePresentation.avatar(base: base, update: update,
            profile: makeProfile(id: "reddit:someone-else")))
        XCTAssertNil(NativeBaseQuotePresentation.avatar(base: base, update: update,
            profile: makeProfile(platform: "x")))
    }

    private func makeProfile(id: String = "reddit:bflo-retail", platform: String = "Reddit") -> SmartAccountProfile {
        SmartAccountProfile(id: id, name: "u/BFLO-Retail", handle: "BFLO-Retail",
            platform: platform, score: 0, scoreChange: 0, specialty: "", horizon: "unknown", recentTicker: "CRWD",
            platformPercentile: 1, confidence: "", topTickers: [], style: "",
            avatarURL: URL(string: "https://i.redd.it/verified-profile.png"))
    }

    private func makeBase(authorID: String = "reddit:bflo-retail") throws -> NativeTradeContext.Base {
        try BSmartJSONCoding.makeDecoder().decode(NativeTradeContext.Base.self, from: Data("""
        {"kind":"opinion","opinionID":"33333333-3333-4333-8333-333333333333",
         "authorID":"\(authorID)","ticker":"CRWD","platform":"reddit",
         "publishedAt":"2026-10-01T08:00:00Z","authorName":"u/BFLO-Retail","avatarURL":null,"body":"Original"}
        """.utf8))
    }
}
