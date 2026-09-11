import XCTest
@testable import BSmart

final class TickerDirectorySectionsTests: XCTestCase {
    private let catalog: [AppTickerCatalogEntry] = [
        .init(symbol: "AAPL", companyName: "Apple", price: 210),
        .init(symbol: "MU", companyName: "Micron"),
        .init(symbol: "NVDA", companyName: "NVIDIA", price: 220, venue: "XYZ", volume24h: 100)
    ]

    func testTrendingKeepsExistingOrderAndQuotesWithoutDuplicatingDirectory() {
        let sections = TickerDirectorySections(catalog: catalog, trendingSymbols: [" nvda ", "$MU", "NVDA", "UNKNOWN"])
        XCTAssertEqual(sections.trending.map(\.symbol), ["NVDA", "MU"])
        XCTAssertEqual(sections.remaining.map(\.symbol), ["AAPL"])
        XCTAssertEqual(sections.matchCount, catalog.count)
        XCTAssertEqual(sections.trending[0], catalog[2])
        XCTAssertNil(sections.trending[1].price)
    }

    func testSearchIncludesTrendingAndOtherSymbolsAndCompanyNames() {
        for (query, expected) in [(" nvDa ", "NVDA"), ("apple", "AAPL"), ("micron", "MU")] {
            let sections = TickerDirectorySections(catalog: catalog, trendingSymbols: ["NVDA"], query: query)
            XCTAssertTrue(sections.trending.isEmpty)
            XCTAssertEqual(sections.remaining.map(\.symbol), [expected])
            XCTAssertEqual(sections.matchCount, 1)
        }
    }

    func testMissingTrendingDoesNotHideAnySupportedTicker() {
        let sections = TickerDirectorySections(catalog: catalog, trendingSymbols: [])
        XCTAssertTrue(sections.trending.isEmpty)
        XCTAssertEqual(sections.remaining, catalog)
        XCTAssertEqual(TickerDirectorySections(catalog: catalog, trendingSymbols: ["NVDA"], query: "missing").matchCount, 0)
    }
}
