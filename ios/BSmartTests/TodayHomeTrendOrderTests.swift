import XCTest
import UIKit
@testable import BSmart

final class TodayHomeTrendOrderTests: XCTestCase {
    private let now = SubjectFeedDay.parse("2026-10-01")

    func testFeaturedSubjectsLeadInRequestedOrderWithoutChangingFilingDates() throws {
        let ids = TodayHomeTrendOrder.featuredSubjectIDs
        let snapshot = try snapshot(ids: ids.reversed().map { $0 }, events: ids.map {
            event(subject: $0, day: "2026-08-14")
        } + [event(subject: ids[0], day: "2026-09-25")])
        let items = TodayHomeTrendOrder.activities(updates: [], movements: [], snapshot: snapshot, now: now)
        XCTAssertEqual(items.map(\.actorID), ids)
        XCTAssertEqual(items[0].occurredAt, SubjectFeedDay.parse("2026-09-25"))
        XCTAssertEqual(items[1].occurredAt, SubjectFeedDay.parse("2026-08-14"))
        XCTAssertEqual(Set(items.map(\.actorID)).count, items.count)
    }

    func testMissingStaleFutureAndSampleSubjectsAreNotInvented() throws {
        let ids = TodayHomeTrendOrder.featuredSubjectIDs
        let snapshot = try snapshot(ids: ids, events: [
            event(subject: ids[0], day: "2025-01-01"),
            event(subject: ids[1], day: "2026-10-02"),
            event(subject: ids[2], day: "2026-09-30", sample: true),
            event(subject: ids[3], day: "2026-08-14"),
        ])
        let items = TodayHomeTrendOrder.activities(updates: [], movements: [], snapshot: snapshot, now: now)
        XCTAssertEqual(items.map(\.actorID), [ids[3]])
    }

    func testRecentActorsFillRemainingSlotsAndLimitIsRespected() throws {
        let featured = TodayHomeTrendOrder.featuredSubjectIDs[0]
        let others = ["institution:other-a", "institution:other-b", "institution:old"]
        let snapshot = try snapshot(ids: [featured] + others, events: [
            event(subject: featured, day: "2026-09-30"),
            event(subject: featured, day: "2026-09-29"),
            event(subject: others[0], day: "2026-09-30"),
            event(subject: others[1], day: "2026-09-29"),
            event(subject: others[2], day: "2026-08-14"),
        ])
        let all = TodayHomeTrendOrder.activities(updates: [], movements: [], snapshot: snapshot, now: now)
        XCTAssertEqual(all.map(\.actorID), [featured] + Array(others.prefix(2)))
        XCTAssertEqual(TodayHomeTrendOrder.activities(updates: [], movements: [], snapshot: snapshot,
                                                     now: now, limit: 1).map(\.actorID), [featured])
        XCTAssertTrue(TodayHomeTrendOrder.activities(updates: [], movements: [], snapshot: snapshot,
                                                    now: now, limit: 0).isEmpty)
    }

    func testPublishedBundleHasAllFeaturedIdentitiesWithRealEvents() {
        let snapshot = TodaySubjectFeedSnapshot.bundled
        let items = TodayHomeTrendOrder.activities(updates: [], movements: [], snapshot: snapshot, now: now)
        let count = TodayHomeTrendOrder.featuredSubjectIDs.count
        XCTAssertEqual(Array(items.prefix(count)).map(\.actorID), TodayHomeTrendOrder.featuredSubjectIDs)
        XCTAssertTrue(items.prefix(count).contains { $0.actorID == "celebrity:warren-buffett" })
        for item in items.prefix(count) {
            guard case let .subject(value, parent) = item else { return XCTFail("Expected a real subject") }
            XCTAssertFalse(value.latest.isSample)
            XCTAssertNotNil(value.latest.sourceURL)
            XCTAssertNotNil(parent.subject.avatarURL)
            XCTAssertNotNil(UIImage(named: parent.subject.bundledAvatarAssetName))
        }
    }

    func testSubjectAvatarNamesMatchSharedBundledAssets() {
        XCTAssertEqual(TodaySubjectProfile.avatarAssetName(for: "politician:P000197"),
                       "SubjectAvatar_politician_P000197")
        XCTAssertEqual(TodaySubjectProfile.avatarAssetName(for: "celebrity:warren-buffett"),
                       "SubjectAvatar_celebrity_warren_buffett")
        XCTAssertEqual(TodaySubjectProfile.avatarAssetName(for: "institution:citadel"),
                       "SubjectAvatar_institution_citadel")
    }

    private func event(subject: String, day: String, sample: Bool = false) -> [String: Any] {
        ["id": "\(subject):\(day)", "subjectID": subject, "ticker": "AAPL", "type": "holding",
         "action": "held", "assetName": "APPLE INC", "occurredDay": "2026-06-30",
         "displayDay": day, "sourceURL": "https://www.sec.gov/Archives/example", "isSample": sample]
    }

    private func snapshot(ids: [String], events: [[String: Any]]) throws -> TodaySubjectFeedSnapshot {
        let subjects: [[String: Any]] = ids.map {
            ["id": $0, "kind": String($0.split(separator: ":")[0]), "name": $0]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "subjects": subjects, "events": events,
        ])
        return try JSONDecoder().decode(TodaySubjectFeedSnapshot.self, from: data)
    }
}
