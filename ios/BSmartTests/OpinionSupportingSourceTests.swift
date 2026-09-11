import XCTest
@testable import BSmart

final class OpinionSupportingSourceTests: XCTestCase {
    private func example() async throws -> SmartAccountUpdate {
        let evidence = try await BundleBSmartAPIClient().fetchSmartAccountEvidence(accountID: "1018427617")
        return try XCTUnwrap(evidence.first { $0.id.uuidString.lowercased() == "dc0b0c28-2e07-55e5-91be-e4db8c7a47fa" })
    }

    private func changed(_ source: OpinionSupportingSource, key: String, value: Any) throws -> OpinionSupportingSource {
        let encoded = try JSONEncoder().encode(source)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object[key] = value
        return try JSONDecoder().decode(OpinionSupportingSource.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testReviewedFixtureHasClaimScopedContextWithoutChangingScore() async throws {
        let update = try await example()
        let source = try XCTUnwrap(update.displayableSupportingSources.first)
        XCTAssertEqual(source.sourceType, "regulatory")
        XCTAssertEqual(source.publisher, "Nebius Group · SEC EDGAR")
        XCTAssertEqual(source.relationship, "related")
        XCTAssertTrue(update.originalText!.contains(source.claim))
        XCTAssertEqual(source.originalURL?.host, "www.sec.gov")
        XCTAssertLessThan(source.publishedAt, update.publishedAt)
        var withoutContext = update
        withoutContext.supportingSources = nil
        XCTAssertTrue(withoutContext.displayableSupportingSources.isEmpty)
        XCTAssertEqual(update.score, withoutContext.score)
        XCTAssertEqual(update.thesis, withoutContext.thesis)
    }

    func testAllFactualSourceKindsAreSupported() async throws {
        var update = try await example()
        let source = try XCTUnwrap(update.supportingSources?.first)
        for kind in ["company", "regulatory", "news", "research", "data", "other"] {
            update.supportingSources = [try changed(source, key: "sourceType", value: kind)]
            XCTAssertEqual(update.displayableSupportingSources.count, 1, kind)
        }
    }

    func testAbsentInvalidWithdrawnAndUnrelatedContextIsInvisible() async throws {
        var update = try await example()
        let source = try XCTUnwrap(update.supportingSources?.first)
        for (key, value) in [("status", "withdrawn"), ("claim", "Not in the original"),
                             ("excerpt", " "), ("ticker", "NVDA"), ("relationship", "unknown"),
                             ("sourceURL", "file:///tmp/a"), ("sourceURL", "https://127.0.0.1/a"),
                             ("sourceURL", "https://[::1]/a"), ("sourceURL", "https://u:p@example.com/a")] {
            update.supportingSources = [try changed(source, key: key, value: value)]
            XCTAssertTrue(update.displayableSupportingSources.isEmpty, "\(key): \(value)")
        }
        update.supportingSources = [source]
        update.originalText = "I expect a bounce off the moving average."
        XCTAssertTrue(update.displayableSupportingSources.isEmpty)
    }

    func testFutureAndLaterDocumentsAreNotHistoricalCitations() async throws {
        let update = try await example()
        let source = try XCTUnwrap(update.supportingSources?.first)
        let later = try changed(source, key: "publishedAt", value: update.publishedAt.addingTimeInterval(60).timeIntervalSinceReferenceDate)
        XCTAssertFalse(later.isDisplayable(for: update))
        let followUp = try changed(later, key: "relationship", value: "follow_up")
        XCTAssertTrue(followUp.isDisplayable(for: update))
        XCTAssertFalse(followUp.isDisplayable(for: update, now: update.publishedAt))
    }

    func testURLAndIDDuplicatesAreHiddenAndOldPayloadsDecode() async throws {
        var update = try await example()
        let source = try XCTUnwrap(update.supportingSources?.first)
        let duplicate = try changed(try changed(source, key: "id", value: "another"), key: "sourceURL", value: source.sourceURL + "#section")
        update.supportingSources = [source, source, duplicate]
        XCTAssertEqual(update.displayableSupportingSources.count, 1)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(update)) as? [String: Any])
        object.removeValue(forKey: "supportingSources")
        let legacy = try JSONDecoder().decode(SmartAccountUpdate.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.supportingSources)
        XCTAssertTrue(legacy.displayableSupportingSources.isEmpty)
    }

    func testRevisedSourceCannotMasqueradeAsHistoricalEvidence() async throws {
        let update = try await example()
        let original = try XCTUnwrap(update.supportingSources?.first)
        var revised = original
        revised.updatedAt = update.publishedAt.addingTimeInterval(60)
        XCTAssertFalse(revised.isDisplayable(for: update))
        let followUp = try changed(revised, key: "relationship", value: "follow_up")
        XCTAssertTrue(followUp.isDisplayable(for: update))
        XCTAssertEqual(followUp.publishedAt, original.publishedAt)
        XCTAssertFalse(followUp.isDisplayable(for: update, now: update.publishedAt))
        revised.updatedAt = original.publishedAt.addingTimeInterval(-60)
        XCTAssertFalse(revised.isDisplayable(for: update))
    }

    func testLocalCrawledSamplesDecodeAndRemainClaimScoped() async throws {
        let updates = try await BundleBSmartAPIClient().fetchSmartAccountUpdates()
        let expectedCounts = [
            "10f4b6d2-018d-57ec-9826-3d492ae7c407": 1,
            "1fd8eff9-e068-522f-8fa8-893a706d99d7": 1,
            "37e03074-4551-5cff-8073-e53fc6cd730e": 2,
            "54e97ed5-1cd0-5cb2-95b9-ac644bff7d74": 1
        ]
        for (id, count) in expectedCounts {
            let update = try XCTUnwrap(updates.first { $0.id.uuidString.lowercased() == id })
            XCTAssertEqual(update.displayableSupportingSources.count, count, id)
            for source in update.displayableSupportingSources {
                XCTAssertTrue(update.originalText!.contains(source.claim))
                XCTAssertNotEqual(source.relationship, "cited")
            }
        }
        let technical = try XCTUnwrap(updates.first {
            $0.id.uuidString.lowercased() == "cdb16cea-8f87-582d-80b1-c03a4b401c0e"
        })
        XCTAssertTrue(technical.displayableSupportingSources.isEmpty)
    }
}
