import XCTest
@testable import BSmart

final class InvestorEducationTests: XCTestCase {
    func testBundledSnapshotAndAtlasAreAvailable() throws {
        let data = try InvestorEducationSnapshot.load()
        XCTAssertTrue(data.isValid)
        let x = try XCTUnwrap(data.platforms.first { $0.id == "x" })
        XCTAssertGreaterThanOrEqual(x.totalObserved, 1000)
        XCTAssertGreaterThanOrEqual(data.authors.count, 800)
        XCTAssertEqual(Set(data.authors.map(\.id)).count, data.authors.count)
        XCTAssertEqual(x.selectedCount, Int(Double(x.rankedCount) * 0.25))
        let url = try XCTUnwrap(Bundle.main.url(forResource: "InvestorEducationAtlas", withExtension: "jpg"))
        XCTAssertLessThan(try Data(contentsOf: url).count, 2_000_000)
        XCTAssertLessThan(data.atlasWidth * data.atlasHeight * 4, 28_000_000)
    }

    func testPlatformPoolsUseTheirOwnAuthorsAndPublishedRankThresholds() throws {
        let data = try InvestorEducationSnapshot.load()
        let expected = [("x", 1283, 234, 58, 881), ("youtube", 300, 88, 22, 280), ("reddit", 192, 31, 7, 100)]
        for (id, observed, ranked, selected, minimumPortraits) in expected {
            let platform = try XCTUnwrap(data.platforms.first { $0.id == id })
            XCTAssertTrue(platform.isValid)
            XCTAssertEqual(platform.totalObserved, observed)
            XCTAssertEqual(platform.rankedCount, ranked)
            XCTAssertEqual(platform.selectedCount, selected)
            XCTAssertGreaterThanOrEqual(platform.authors.count, minimumPortraits)
            XCTAssertEqual(platform.headlineCount, id == "x" ? "1000+" : String(observed))
        }
        XCTAssertEqual(Set(data.authors.map(\.tile)).count, data.authors.count)
        let youtube = try XCTUnwrap(data.platforms.first { $0.id == "youtube" })
        let wrongPlatform = InvestorEducationSnapshot.Platform(id: "reddit", name: "Reddit", totalObserved: 300,
                                                               rankedCount: 88, selectedCount: 22, authors: youtube.authors)
        XCTAssertFalse(wrongPlatform.isValid)
        XCTAssertEqual(data.displayPlatforms.map(\.id), ["youtube", "x", "reddit"])
        XCTAssertEqual(data.displayPlatforms[1].id, InvestorEducationSnapshot.defaultPlatformID)
    }

    func testPositiveExampleKeepsOnePostAndItsSettlementWindow() throws {
        let example = try InvestorEducationSnapshot.load().example
        XCTAssertEqual(example.authorID, "1707559719215489024")
        XCTAssertEqual(example.ticker, "SNDK")
        XCTAssertEqual(example.publishedDay, "2025-11-09")
        XCTAssertEqual(example.entryDay, "2025-11-10")
        XCTAssertEqual(example.exitDay, "2026-02-05")
        XCTAssertEqual(example.horizon, "60D")
        XCTAssertGreaterThan(example.contribution, 0)
        XCTAssertEqual(example.returnPercent, 133.28, accuracy: 0.01)
        XCTAssertEqual((example.exitPrice / example.entryPrice - 1) * 100, example.returnPercent, accuracy: 0.01)
        XCTAssertTrue(example.sourceURL.hasSuffix("1987365274408874017"))
        XCTAssertEqual(example.candles.last?.day, example.exitDay)
    }

    @MainActor
    func testEveryAtlasTileDecodesWithoutChangingAuthorOrder() throws {
        let data = try InvestorEducationSnapshot.load()
        let artwork = InvestorEducationArtwork(snapshot: data)
        XCTAssertEqual(artwork.tiles.count, data.authors.count)
        XCTAssertTrue(data.authors.allSatisfy { artwork.tiles[$0.tile] != nil })
        XCTAssertTrue(data.authors.contains { $0.id == data.example.authorID })
    }
}
