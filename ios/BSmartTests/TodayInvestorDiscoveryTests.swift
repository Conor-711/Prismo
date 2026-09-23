import XCTest
@testable import BSmart

final class TodayInvestorDiscoveryTests: XCTestCase {
    func testRequiresExplicitValidPlatformPercentileAndRankWithoutRescoring() {
        var unranked = author("unranked")
        unranked.rank = nil
        unranked.platformRank = nil
        let inputs = [author("top", percentile: 0), author("boundary", percentile: 0.25),
                      author("outside", percentile: 0.25001), author("missing", percentile: nil),
                      author("invalid", percentile: -.infinity), author("nan", percentile: .nan), unranked]
        let discovery = projection(inputs)
        XCTAssertEqual(discovery.investors.map(\.account.id), ["top", "boundary"])
        XCTAssertEqual(discovery.investors.first?.account.score, 123)
        XCTAssertEqual(discovery.investors, projection(Array(inputs.reversed())).investors)
    }

    func testIdentityIsPlatformScopedAndIgnoresCaseAndTwitterAliases() {
        let accounts = [author("a"), author(" A ", platform: "Twitter"), author("a", platform: "YouTube")]
        let discovery = projection(accounts)
        XCTAssertEqual(discovery.investors.count, 2)
        XCTAssertEqual(Set(discovery.investors.map(\.id)), ["x:a", "youtube:a"])
    }

    func testSharedSectorMatchesAuthorSpecialtyNotOpinionTickerAndSearchIntersects() {
        let accounts = [author("chip", sector: "Semiconductors"), author("software", sector: "Software")]
        let discovery = projection(accounts)
        XCTAssertEqual(discovery.candidates(sector: "Semiconductors").map(\.account.id), ["chip"])
        XCTAssertEqual(discovery.candidates(sector: "Semiconductors", query: " SOFTWARE ").count, 0)
        XCTAssertEqual(discovery.candidates(sector: "Semiconductors", query: " nvda ").count, 1)
        XCTAssertEqual(discovery.sectors, ["Semiconductors", "Software"])
    }

    func testPreferredIdentityAndThreeYouTubePortraitsWithoutChangingRanksOrCoverage() {
        let inputs = [author("1940360837547565056", percentile: 0.141026)]
            + (0..<16).map { author("x\($0)") }
            + (0..<8).map { author("video\($0)", platform: "YouTube", avatar: true) }
        let discovery = projection(inputs)
        let arranged = TodayInvestorPool.arranged(discovery.investors)
        XCTAssertEqual(arranged[2].id, TodayInvestorPool.preferredID)
        XCTAssertEqual(arranged.prefix(4).filter { $0.account.platform == "YouTube" }.count, 3)
        XCTAssertEqual(Set(arranged), Set(discovery.investors))
        XCTAssertEqual(arranged.count, discovery.investors.count)
        XCTAssertEqual(arranged[2].account.platformPercentile, 0.141026)
        XCTAssertEqual(TodayInvestorPool.topPercent(arranged[2]), 15)
        XCTAssertEqual(arranged, TodayInvestorPool.arranged(projection(Array(inputs.reversed())).investors))
    }

    func testPreferredAuthorNeverBypassesEligibilityOrSectorFilter() {
        let discovery = projection([author("1940360837547565056", percentile: 0.26), author("a")])
        XCTAssertEqual(TodayInvestorPool.arranged(discovery.investors).first?.id, "x:a")
        let sectors = projection([author("1940360837547565056", sector: "Software"), author("a")])
        XCTAssertEqual(TodayInvestorPool.arranged(sectors.candidates(sector: "Semiconductors")).map(\.id), ["x:a"])
        let alias = projection([author("1940360837547565056", platform: "Reddit"), author("a", percentile: 0.01)])
        XCTAssertEqual(TodayInvestorPool.arranged(alias.investors).first?.id, "x:a")
    }

    func testOpeningFiveIncludeRedditWithoutChangingTheDefaultOrRanks() {
        let inputs = [author("1940360837547565056"),
                      author("redditLeader", platform: "Reddit", percentile: 0.04),
                      author("redditOther", platform: "Reddit", percentile: 0.12, avatar: true)]
            + (0..<8).map { author("video\($0)", platform: "YouTube", avatar: true) }
            + (0..<16).map { author("x\($0)") }
        let candidates = projection(inputs).investors
        let arranged = TodayInvestorPool.arranged(candidates)
        XCTAssertEqual(arranged[2].id, TodayInvestorPool.preferredID)
        XCTAssertEqual(arranged[4].id, "reddit:redditother")
        XCTAssertEqual(arranged.prefix(5).filter { $0.account.platform == "YouTube" }.count, 3)
        XCTAssertEqual(Set(arranged.prefix(5).map(\.account.platform)), ["X", "YouTube", "Reddit"])
        XCTAssertEqual(arranged.count, candidates.count)
        XCTAssertEqual(Set(arranged), Set(candidates))
        XCTAssertEqual(arranged, TodayInvestorPool.arranged(projection(Array(inputs.reversed())).investors))
    }

    func testRedditPlacementPreservesEligibilitySectorAndSmallPoolCoverage() {
        let discovery = projection([author("a"), author("outside", platform: "Reddit", percentile: 0.26),
                                    author("otherSector", platform: "Reddit", sector: "Software")])
        XCTAssertEqual(TodayInvestorPool.arranged(discovery.candidates(sector: "Semiconductors")).map(\.id), ["x:a"])
        for count in [0, 1, 2, 8] {
            let candidates = projection((0..<count).map { author("a\($0)", platform: "Reddit") }).investors
            let arranged = TodayInvestorPool.arranged(candidates)
            XCTAssertEqual(arranged.count, candidates.count)
            XCTAssertEqual(Set(arranged), Set(candidates))
        }
    }

    func testBundledOpeningGroupIncludesAllThreePlatforms() async throws {
        let accounts = try await BundleBSmartAPIClient().fetchSmartAccounts()
        let arranged = TodayInvestorPool.arranged(projection(accounts).investors)
        XCTAssertEqual(arranged[2].id, TodayInvestorPool.preferredID)
        XCTAssertEqual(Set(arranged.prefix(5).map(\.account.platform)), ["X", "YouTube", "Reddit"])
        XCTAssertEqual(arranged[4].account.name, "u/Smart_Money_HQ")
        XCTAssertNotNil(arranged[4].account.avatarURL)
        XCTAssertEqual(arranged[1].account.name, "u/alpha247365")
        XCTAssertEqual(arranged[3].account.name.trimmingCharacters(in: .whitespaces), "Jeremy Lefebvre Clips")
        XCTAssertEqual(TodayRepresentativeStoryBundle.bundled?.story(for: arranged[1].account)?.ticker, "TQQQ")
        XCTAssertNotNil(TodayRepresentativeStoryBundle.bundled?.story(for: arranged[3].account))
        XCTAssertEqual(Set(arranged), Set(projection(accounts).investors))
        XCTAssertTrue(arranged.dropFirst(5).contains { $0.account.name == "Rey Jay's Trades" })
    }

    func testPortraitsPrecedePlaceholdersAndPreserveOrderWithinEachGroup() {
        let candidates = projection([
            author("missing", platform: "Reddit", percentile: 0.01),
            author("photoFirst", platform: "Reddit", percentile: 0.03, avatar: true),
            author("photoSecond", platform: "Reddit", percentile: 0.1, avatar: true),
            author("missingSecond", platform: "Reddit", percentile: 0.15)
        ]).investors
        let arranged = TodayInvestorPool.arranged(candidates)
        XCTAssertEqual(arranged.map(\.account.id), ["photoFirst", "photoSecond", "missing", "missingSecond"])
        XCTAssertEqual(Set(arranged), Set(candidates))
    }

    func testBundledRedditFallbackAlsoGetsPortraitPriority() {
        var known = author("smart_money_hq", platform: "Reddit", percentile: 0.1)
        known = SmartAccountProfile(id: known.id, name: "u/Smart_Money_HQ", handle: "u/Smart_Money_HQ",
            platform: known.platform, score: known.score, scoreChange: known.scoreChange,
            specialty: known.specialty, horizon: known.horizon, recentTicker: known.recentTicker,
            platformRank: 2, platformPercentile: 0.1)
        let candidates = projection([author("missing", platform: "Reddit", percentile: 0.01), known]).investors
        let arranged = TodayInvestorPool.arranged(candidates)
        XCTAssertEqual(arranged.first?.account.id, known.id)
        XCTAssertNil(arranged.first?.account.avatarURL)
        XCTAssertEqual(Set(arranged), Set(candidates))
    }

    func testYouTubeWithoutPhotoStaysInPoolButDoesNotDisplaceAvailablePortraits() {
        let accounts = (0..<15).map { author("a\($0)") }
            + [author("noPhoto", platform: "YouTube", percentile: 0.001)]
            + (0..<4).map { author("photo\($0)", platform: "YouTube", avatar: true) }
        let arranged = TodayInvestorPool.arranged(projection(accounts).investors)
        XCTAssertTrue(arranged.contains { $0.account.id == "noPhoto" })
        XCTAssertEqual(arranged.prefix(4).filter { $0.account.platform == "YouTube" && $0.account.avatarURL != nil }.count, 4)
    }

    func testHorizontalPoolCoversEveryAuthorExactlyOnceIncludingSmallAndEmptyPools() {
        for count in [0, 1, 2, 8, 9, 10, 87] {
            let candidates = projection((0..<count).map { author("a\($0)", platform: "YouTube", avatar: true) }).investors
            let arranged = TodayInvestorPool.arranged(candidates)
            XCTAssertEqual(Set(arranged), Set(candidates))
            XCTAssertEqual(arranged.count, candidates.count)
        }
    }

    func testSearchUsesDisplayedSectorAndStyleLabelsWithoutChangingCohort() {
        let discovery = projection([author("chip"), author("other", sector: "Software")])
        let labels = ["Semiconductors": "\u{534a}\u{5bfc}\u{4f53}", "Software": "\u{8f6f}\u{4ef6}"]
        XCTAssertEqual(discovery.candidates(sector: nil, query: labels["Semiconductors"]!,
                                           localize: { labels[$0] ?? $0 }).map(\.account.id), ["chip"])
        XCTAssertTrue(discovery.candidates(sector: "Software", query: labels["Semiconductors"]!,
                                          localize: { labels[$0] ?? $0 }).isEmpty)
    }

    func testSelectionFallsBackWithoutMutatingPeopleSelection() {
        let discovery = projection([author("a"), author("b")])
        let selection = "x:a"
        XCTAssertEqual(TodayInvestorDiscovery.selected(selection, in: discovery.investors)?.id, "x:a")
        XCTAssertEqual(TodayInvestorDiscovery.selected("missing", in: discovery.investors)?.id, "x:a")
        XCTAssertEqual(TodayInvestorDiscovery.selected(selection, in: discovery.investors)?.id, "x:a")
        XCTAssertNil(TodayInvestorDiscovery.selected(selection, in: []))
    }

    func testProfileSessionRetainsCohortAndCannotNavigatePastItsBoundaries() {
        let discovery = projection([author("a"), author("b"), author("outside", sector: "Software")])
        var session = TodayInvestorDiscoverySession(
            investors: discovery.candidates(sector: "Semiconductors"), selectedID: "x:a")
        XCTAssertFalse(session.hasPrevious)
        session.move(by: -1)
        XCTAssertEqual(session.current?.id, "x:a")
        session.move(by: 1)
        XCTAssertEqual(session.current?.id, "x:b")
        XCTAssertFalse(session.hasNext)
        session.move(by: 1)
        XCTAssertEqual(session.current?.id, "x:b")
        let empty = TodayInvestorDiscoverySession(investors: [], selectedID: "missing")
        XCTAssertNil(empty.current)
        XCTAssertFalse(empty.hasNext)
    }

    func testRankPercentageNeverRoundsDownOrInventsZeroPercent() {
        let candidates = projection([author("first", percentile: 0), author("edge", percentile: 0.25)]).investors
        XCTAssertEqual(candidates.map { TodayInvestorPool.topPercent($0) }, [1, 25])
    }

    private func projection(_ accounts: [SmartAccountProfile]) -> TodayInvestorDiscovery {
        TodayInvestorDiscovery(accounts: accounts)
    }

    private func author(_ id: String, platform: String = "X", sector: String = "Semiconductors",
                        percentile: Double? = 0.1, avatar: Bool = false) -> SmartAccountProfile {
        SmartAccountProfile(id: id, name: id, handle: "@\(id)", platform: platform,
                            score: 123, scoreChange: 0, specialty: sector, horizon: "Medium term", recentTicker: "NVDA",
                            rank: 4, platformRank: 4, platformPercentile: percentile,
                            avatarURL: avatar ? URL(string: "https://example.com/\(id).jpg") : nil)
    }
}
