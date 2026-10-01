import XCTest
@testable import BSmart

final class TodayFeedSourceProjectionTests: XCTestCase {
    private let now = SubjectFeedDay.parse("2026-10-01").addingTimeInterval(43_200)

    func testEverySourcePreservesFilteringSortingAndBurstGrouping() throws {
        let items = try fixture()
        let trackedInvestors = Set(items.filter { $0.actorID.contains("youtube") }.map(\.actorID))
        let trackedSubjects: Set<String> = ["politician:p", "institution:i"]
        for type in TodayFeedActivityType.allCases {
            for sort in TodayFeedTimeSort.allCases {
                for trending in [false, true] {
                    for following in [false, true] {
                        let options = TodayFeedDisplayOptions(activityType: type, followingOnly: following,
                            trendingOnly: trending, timeSort: sort)
                        let prepared = TodayFeedSourceProjection.prepare(from: items, options: options,
                            trackedInvestors: trackedInvestors, trackedSubjects: trackedSubjects, now: now)
                        XCTAssertEqual(prepared.count, AccountPlatformFilter.allCases.count)
                        for source in AccountPlatformFilter.allCases {
                            let matching = items.filter { item in
                                switch item {
                                case let .investor(investor):
                                    return source.matches(investor) && type.matches(investor.latest)
                                        && (!following || trackedInvestors.contains(investor.id))
                                case let .subject(subject, _):
                                    return source.matches(subject) && type.matches(subject.latest)
                                        && (!following || trackedSubjects.contains(subject.id))
                                }
                            }
                            let expected = TodayHomeFeedOrder.sorted(TodayHomeFeedItem.mergeAdjacent(matching),
                                trending: trending, timeSort: sort, now: now)
                            let runs = try XCTUnwrap(prepared[source]).runs
                            XCTAssertEqual(runs.flatMap(\.items).map(\.id), expected.map(\.id))
                            XCTAssertEqual(runs.flatMap(\.items).map(\.eventCount), expected.map(\.eventCount))
                            XCTAssertEqual(runs.map(\.hiddenEventCount), TodayHomeFeedRun.consecutive(expected).map(\.hiddenEventCount))
                        }
                    }
                }
            }
        }
    }

    func testPreviewStillExcludesSubjectsAndIgnoresSourceFilter() throws {
        let items = try fixture()
        let prepared = TodayFeedSourceProjection.prepare(from: items,
            options: TodayFeedDisplayOptions(isPreview: true), now: now)
        let expected = items.filter { if case .investor = $0 { return true }; return false }
        for source in AccountPlatformFilter.allCases {
            XCTAssertEqual(prepared[source]?.runs.flatMap(\.items).reduce(0) { $0 + $1.eventCount }, expected.count)
        }
    }

    func testEmptySourcesArePreparedRatherThanReusingAnotherSourcesCards() {
        let prepared = TodayFeedSourceProjection.prepare(from: [], options: .init(), now: now)
        XCTAssertEqual(prepared.count, AccountPlatformFilter.allCases.count)
        XCTAssertTrue(prepared.values.allSatisfy { $0.runs.isEmpty })
    }

    func testDateResolutionIsLinearInBothSortModes() throws {
        let items = try fixture()
        for trending in [false, true] {
            var reads = 0
            _ = TodayHomeFeedOrder.sorted(items, trending: trending, timeSort: .newest, now: now) {
                reads += 1
                return $0.occurredAt
            }
            XCTAssertEqual(reads, items.count)
        }
    }

    func testCancelledPreparationCannotProduceAReplacement() async throws {
        let items = try fixture()
        let worker = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return TodayFeedSourceProjection.prepare(from: items, options: .init())
        }
        worker.cancel()
        let result = await worker.value
        XCTAssertTrue(result.isEmpty)
    }

    func testNewContentAndFollowChangesReplaceEveryPreparedSource() throws {
        let items = try fixture()
        let original = TodayFeedSourceProjection.prepare(from: items, options: .init(), now: now)
        XCTAssertFalse(try XCTUnwrap(original[.politicians]).runs.isEmpty)
        let untracked = TodayFeedSourceProjection.prepare(from: items,
            options: .init(followingOnly: true), now: now)
        XCTAssertTrue(untracked.values.allSatisfy { $0.runs.isEmpty })
        let tracked = TodayFeedSourceProjection.prepare(from: items,
            options: .init(followingOnly: true), trackedSubjects: ["politician:p"], now: now)
        XCTAssertFalse(try XCTUnwrap(tracked[.politicians]).runs.isEmpty)
        XCTAssertTrue(try XCTUnwrap(tracked[.institutions]).runs.isEmpty)
        let next = TodayFeedSourceProjection.prepare(from: [], options: .init(), now: now)
        XCTAssertTrue(next.values.allSatisfy { $0.runs.isEmpty })
    }

    func testBundledFeedPreparationAndCachedSelectionLatency() throws {
        let groups = TodaySubjectActivity.groups(from: .bundled, now: now)
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        let items = groups.flatMap { group in
            group.events.filter { $0.displayedAt >= cutoff || ($0.type == .holding && $0.id == group.latest.id) }
                .map { TodayHomeFeedItem.subject(.init(subject: group.subject, events: [$0]), group) }
        }
        XCTAssertGreaterThan(items.count, 100)
        let merged = TodayHomeFeedItem.mergeAdjacent(items)
        let oldStart = Date.timeIntervalSinceReferenceDate
        let legacy = merged.sorted { lhs, rhs in
            if lhs.occurredAt == rhs.occurredAt { return lhs.id < rhs.id }
            return lhs.occurredAt > rhs.occurredAt
        }
        let oldMS = (Date.timeIntervalSinceReferenceDate - oldStart) * 1000
        let prepareStart = Date.timeIntervalSinceReferenceDate
        let prepared = TodayFeedSourceProjection.prepare(from: items, options: .init(), now: now)
        let prepareMS = (Date.timeIntervalSinceReferenceDate - prepareStart) * 1000
        XCTAssertEqual(prepared[.all]?.runs.flatMap(\.items).map(\.id), legacy.map(\.id))
        let switchStart = Date.timeIntervalSinceReferenceDate
        var count = 0
        for index in 0..<2000 {
            let source = AccountPlatformFilter.allCases[index % AccountPlatformFilter.allCases.count]
            count += try XCTUnwrap(prepared[source]).runs.count
        }
        let switchMS = (Date.timeIntervalSinceReferenceDate - switchStart) * 1000
        XCTAssertGreaterThan(count, 0)
        XCTAssertLessThan(switchMS, 250, "Cached selection must not re-filter or sort the feed")
        print("SOURCE_PROJECTION_BENCHMARK items=\(items.count) legacyAllMS=\(oldMS) prepareAllSourcesMS=\(prepareMS) cached2000SelectionsMS=\(switchMS)")
    }

    private func fixture() throws -> [TodayHomeFeedItem] {
        let updates = ["X", "Twitter", "YouTube", "Reddit", "bsmart"].enumerated().flatMap { index, source in
            (0..<3).map { offset in
                SmartAccountUpdate(id: UUID(), ticker: offset < 2 ? "AAPL" : "TSLA", companyName: "Asset",
                    authorId: "actor-\(index)", authorName: "Actor", platform: source, score: 120,
                    platformPercentile: 0.1, direction: .bullish, lifecycle: .new, horizon: "20D",
                    targetPrice: nil, thesis: "Thesis", invalidation: nil,
                    publishedAt: now.addingTimeInterval(-Double(index * 100 + offset * 10)), evidenceURL: nil)
            }
        }
        let investors = TodayInvestorActivity.groups(accountUpdates: updates, moneyMovements: [], now: now)
        let native = investors.flatMap { investor in
            investor.activities.map { TodayHomeFeedItem.investor(.init(id: investor.id, activities: [$0])) }
        }
        let subjects: [[String: Any]] = [
            ["id": "politician:p", "kind": "politician", "name": "Politician"],
            ["id": "celebrity:c", "kind": "celebrity", "name": "Figure"],
            ["id": "institution:i", "kind": "institution", "name": "Institution"],
        ]
        let events = subjects.flatMap { profile in
            ["trade", "opinion", "holding"].enumerated().map { index, type -> [String: Any] in
                ["id": "\(profile["id"]!)-\(index)", "subjectID": profile["id"]!, "type": type,
                 "ticker": "AAPL", "assetName": "APPLE INC", "action": type == "holding" ? "increased" : "buy",
                 "direction": "bullish", "summary": "Thesis", "occurredDay": "2026-09-28",
                 "displayDay": "2026-09-30", "sourceURL": "https://www.sec.gov/example", "isSample": false]
            }
        }
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "subjects": subjects, "events": events])
        let snapshot = try JSONDecoder().decode(TodaySubjectFeedSnapshot.self, from: data)
        XCTAssertTrue(snapshot.isValid)
        let others = TodaySubjectActivity.groups(from: snapshot, now: now).flatMap { subject in
            subject.events.map { TodayHomeFeedItem.subject(.init(subject: subject.subject, events: [$0]), subject) }
        }
        return native + others
    }
}
