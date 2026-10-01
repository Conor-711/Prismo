import XCTest
@testable import BSmart

@MainActor
final class InvestorAbilityLeaderboardTests: XCTestCase {
    private func decode(_ rows: String, status: String = "published") throws -> InvestorAbilityLeaderboard {
        let metadata = status == "published" ? "\"revision\":1,\"asOf\":\"2026-09-29T00:00:00Z\"" : "\"revision\":null,\"asOf\":null"
        let data = Data("{\"status\":\"\(status)\",\"version\":\"follow-ability-v1\",\(metadata),\"scoreUnit\":\"annualized_adjusted_pp\",\"items\":[\(rows)]}".utf8)
        return try BSmartJSONCoding.makeDecoder().decode(InvestorAbilityLeaderboard.self, from: data)
    }

    private func item(_ kind: String, _ id: String, _ score: String, _ status: String, _ rank: String) -> String {
        "{\"actorKind\":\"\(kind)\",\"actorId\":\"\(id)\",\"displayName\":\"\(id)\",\"platform\":null,\"avatarURL\":null,\"score\":\(score),\"status\":\"\(status)\",\"rank\":\(rank),\"observedCalendarDays\":400,\"independentDecisionDays\":20,\"pricedCoverage\":0.9}"
    }

    func testUnboundedScoresAndTiedRanks() throws {
        let rows = [item("platform", "a", "178.5", "scored", "1"),
                    item("politician", "b", "178.5", "scored", "1"),
                    item("institution", "c", "-17.2", "scored", "3"),
                    item("celebrity", "d", "null", "insufficient_history", "null")].joined(separator: ",")
        let snapshot = try decode(rows).validate()
        XCTAssertEqual(snapshot.items.map(\.rank), [1, 1, 3, nil])
        XCTAssertEqual(snapshot.items[0].scoreLabel, "+178.5")
        XCTAssertEqual(snapshot.items[2].score, -17.2)
        XCTAssertNotNil(try decode("", status: "unpublished").validate())
    }

    func testRejectsLegacyOrMisrankedScores() throws {
        let legacy = try decode(item("platform", "a", "null", "scored", "1"))
        XCTAssertThrowsError(try legacy.validate())
        let wrongRank = try decode(item("platform", "a", "2", "scored", "2"))
        XCTAssertThrowsError(try wrongRank.validate())
        let outOfOrder = try decode([item("platform", "a", "1", "scored", "1"),
                                     item("institution", "b", "2", "scored", "2")].joined(separator: ","))
        XCTAssertThrowsError(try outOfOrder.validate())
    }

    func testMockUsesRealSubjectsAndStableClearlySeparateScores() throws {
        let account = SmartAccountProfile(id: "x:sample", name: "Sample account", handle: "sample",
                                          platform: "x", score: 100, scoreChange: 0,
                                          specialty: "", horizon: "", recentTicker: nil)
        let subjects = [
            TodaySubjectProfile(id: "politician:one", kind: .politician, name: "Politician One", avatarURL: nil, metrics: nil),
            TodaySubjectProfile(id: "institution:two", kind: .institution, name: "Institution Two", avatarURL: nil, metrics: nil)
        ]
        let first = try InvestorAbilityLeaderboard.mock(accounts: [account], subjects: subjects).validate()
        let second = InvestorAbilityLeaderboard.mock(accounts: [account], subjects: subjects)
        XCTAssertEqual(first.status, .mock)
        XCTAssertEqual(first.scoreUnit, "mock_points")
        XCTAssertNil(first.asOf)
        XCTAssertEqual(first.items.count, 3)
        XCTAssertEqual(first.items.map(\.id), second.items.map(\.id))
        XCTAssertEqual(first.items.map(\.score), second.items.map(\.score))
        XCTAssertEqual(Set(first.items.map(\.actorKind)), [.platform, .politician, .institution])
    }

    func testStoreDiscardsStaleResponses() async throws {
        let store = InvestorAbilityLeaderboardStore()
        let ready = try decode(item("platform", "a", "3", "scored", "1"))
        await store.load { ready }
        XCTAssertEqual(store.snapshot?.items.count, 1)
        await store.load { store.clear(); return ready }
        XCTAssertNil(store.snapshot)
    }

    func testBundledResearchHasExplicitStatusAndRealObservations() throws {
        let snapshot = try XCTUnwrap(InvestorAbilityLeaderboard.bundledResearch)
        XCTAssertEqual(snapshot.status, .research)
        XCTAssertEqual(snapshot.scoreUnit, "research_candidate_pp")
        XCTAssertEqual(snapshot.items.count, 1_920)
        XCTAssertTrue(snapshot.items.contains {
            $0.actorKind == .politician && $0.winRate != nil && ($0.winRateObservations ?? 0) > 0
        })
        XCTAssertTrue(snapshot.items.contains {
            $0.actorKind == .platform && $0.winRate != nil && $0.followReturn != nil
        })
        XCTAssertTrue(snapshot.items.contains {
            $0.actorKind == .platform && $0.winRateObservations == 1 && $0.followReturn != nil
        })
        XCTAssertFalse(snapshot.items.contains { $0.winRate != nil && $0.followReturn == nil })
        let hern = try XCTUnwrap(snapshot.items.first { $0.displayName == "Kevin Hern" })
        XCTAssertEqual(hern.followReturnMethod, "directional_30d_proxy")
        XCTAssertNotNil(hern.followReturn)
    }

    func testServerSubjectResearchReplacesStaleBundledMetricsWithoutCreatingScore() throws {
        let payload = """
        {"id":"politician:A000001","kind":"politician","name":"Example","avatarURL":null,"metrics":null,
         "research":{"method":"three_year_open_positions_v1","asOf":"2026-09-30",
         "sourceSince":"2023-09-30","latestMarketDate":"2026-09-29",
         "candidatePositions":3,"pricedPositions":2,"directionalWins":4,"directionalLosses":3,
         "directionalObservations":8,"directionalWinRate":0.5,
         "openPositionPositiveRate":0.5,"meanOpenReturn":0.12}}
        """
        let subject = try JSONDecoder().decode(TodaySubjectProfile.self, from: Data(payload.utf8))
        XCTAssertTrue(try XCTUnwrap(subject.research).isValid)
        XCTAssertEqual(subject.research?.winRateFromDecidedOutcomes, 4.0 / 7.0)
        let bundled = try XCTUnwrap(InvestorAbilityLeaderboard.bundledResearch)
        let replaced = try bundled.replacingSubjectResearch(with: [subject]).validate()
        let item = try XCTUnwrap(replaced.items.first { $0.actorId == subject.id })
        XCTAssertNil(item.score)
        XCTAssertNil(item.rank)
        XCTAssertEqual(item.winRateWins, 4)
        XCTAssertEqual(item.winRateLosses, 3)
        XCTAssertEqual(item.winRateObservations, 7)
        XCTAssertEqual(item.winRate, 4.0 / 7.0)
        XCTAssertEqual(item.followReturn, 0.12)
        XCTAssertEqual(item.followReturnMethod, "open_position_equal_weight_absolute")
        XCTAssertTrue(replaced.items.contains { $0.actorKind == .platform && $0.score != nil })
    }

    func testBundledSubjectFeedIncludesPublishedResearch() throws {
        let snapshot = TodaySubjectFeedSnapshot.bundled
        XCTAssertTrue(snapshot.isValid)
        XCTAssertEqual(snapshot.subjects.count, 217)
        XCTAssertEqual(snapshot.subjects.compactMap(\.research).count, snapshot.subjects.count)
        let hern = try XCTUnwrap(snapshot.subjects.first { $0.id == "politician:H001082" })
        let research = try XCTUnwrap(hern.research)
        XCTAssertNotNil(research.directionalWinRate)
        XCTAssertNotNil(research.meanOpenReturn)
    }

    func testBalancedMockScoresEveryResearchActorAndMixesTopSources() throws {
        let research = try XCTUnwrap(InvestorAbilityLeaderboard.bundledResearch)
        let subjects = TodaySubjectFeedSnapshot.bundled.subjects
        let source = research.replacingSubjectResearch(with: subjects)
        let first = try source.balancedMock().validate()
        let second = source.balancedMock()
        XCTAssertEqual(first.items.count, source.items.count)
        XCTAssertTrue(first.items.allSatisfy { $0.score != nil && $0.rank != nil })
        XCTAssertEqual(first.items.map(\.id), second.items.map(\.id))
        XCTAssertEqual(first.items.map(\.score), second.items.map(\.score))
        XCTAssertEqual(first.items.prefix(12).map(\.actorKind),
                       [.platform, .politician, .celebrity, .institution,
                        .platform, .politician, .celebrity, .institution,
                        .platform, .politician, .celebrity, .institution])
        let original = try XCTUnwrap(source.items.first { $0.displayName == "Kevin Hern" })
        let mocked = try XCTUnwrap(first.items.first { $0.id == original.id })
        XCTAssertEqual(mocked.winRate, original.winRate)
        XCTAssertEqual(mocked.followReturn, original.followReturn)
    }

    func testCurrentUserHasStableMockPositionInSameRanking() throws {
        let research = try XCTUnwrap(InvestorAbilityLeaderboard.bundledResearch)
        let userID = "00000000-0000-0000-0000-000000000001"
        let first = try research.includingMockUser(id: userID, name: "My profile", avatarURL: nil)
            .balancedMock().validate()
        let second = research.includingMockUser(id: userID, name: "My profile", avatarURL: nil)
            .balancedMock()
        let current = try XCTUnwrap(first.items.first { $0.actorId == "bsmart:\(userID)" })
        XCTAssertEqual(current.actorKind, .platform)
        XCTAssertNotNil(current.score)
        XCTAssertNotNil(current.rank)
        XCTAssertEqual(current.rank, second.items.first { $0.id == current.id }?.rank)
        XCTAssertEqual(first.items.count, research.items.count + 1)
    }
}
