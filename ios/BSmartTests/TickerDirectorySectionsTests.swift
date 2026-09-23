import XCTest
@testable import BSmart

final class TickerDirectorySectionsTests: XCTestCase {
    private let catalog: [AppTickerCatalogEntry] = [
        .init(symbol: "AAPL", companyName: "Apple", price: 210, dayChange: 0.03,
              volume24h: 300),
        .init(symbol: "MU", companyName: "Micron"),
        .init(symbol: "NVDA", companyName: "NVIDIA", price: 220, dayChange: -0.05,
              venue: "XYZ", volume24h: 100),
        .init(symbol: "TSLA", companyName: "Tesla", price: 100, dayChange: 0.08,
              venue: "XYZ", volume24h: 200)
    ]

    func testDefaultSortsAllTickersByVolumeWithMissingVolumesLast() {
        let sections = TickerDirectorySections(catalog: catalog)
        XCTAssertEqual(sections.entries.map(\.symbol), ["AAPL", "TSLA", "NVDA", "MU"])
    }

    func testSearchMatchesSymbolAndCompanyName() {
        for (query, expected) in [(" nvDa ", "NVDA"), ("apple", "AAPL"), ("micron", "MU")] {
            let sections = TickerDirectorySections(catalog: catalog, query: query)
            XCTAssertEqual(sections.entries.map(\.symbol), [expected])
        }
    }

    func testFiltersAndSortCanBeCombined() {
        let mixed = catalog + [
            AppTickerCatalogEntry(symbol: "ETH", companyName: "Ethereum", dayChange: 0.12,
                                  venue: "Hyperliquid", isCrypto: true, volume24h: 900),
            AppTickerCatalogEntry(symbol: "GOLD", companyName: "Gold", venue: "XYZ", volume24h: 500),
            AppTickerCatalogEntry(symbol: "SP500", companyName: "S&P 500", venue: "XYZ", volume24h: 400),
            AppTickerCatalogEntry(symbol: "EUR", companyName: "Euro", venue: "XYZ", volume24h: 200)
        ]
        XCTAssertEqual(TickerDirectorySections(catalog: mixed, filter: .crypto).entries.map(\.symbol), ["ETH"])
        XCTAssertEqual(TickerDirectorySections(catalog: mixed, filter: .commodities).entries.map(\.symbol), ["GOLD"])
        XCTAssertEqual(TickerDirectorySections(catalog: mixed, filter: .indices).entries.map(\.symbol), ["SP500"])
        XCTAssertEqual(TickerDirectorySections(catalog: mixed, filter: .forex).entries.map(\.symbol), ["EUR"])
        XCTAssertEqual(TickerDirectorySections(catalog: mixed, filter: .stocks,
                                               sort: .gain).entries.map(\.symbol), ["TSLA", "AAPL", "NVDA", "MU"])
        XCTAssertEqual(TickerDirectorySections(catalog: mixed, query: "apple", filter: .crypto).entries.count, 0)
        XCTAssertEqual(TickerDirectorySections(catalog: mixed, query: "ethereum", filter: .crypto).entries.map(\.symbol),
                       ["ETH"])
        XCTAssertEqual(TickerDirectoryFilter.category(for: .init(symbol: "SPCX", companyName: "SpaceX")), .stocks)
        XCTAssertEqual(TickerDirectoryFilter.category(for: .init(symbol: "SKHX", companyName: "SK Hynix")), .stocks)
    }

    func testCryptoIdentityDoesNotDependOnDisplayVenue() {
        let native = AppTickerCatalogEntry(symbol: "NEAR", companyName: "NEAR", price: 4,
                                           venue: "Native perps", isCrypto: true)
        let merged = AppTickerCatalogEntry.merge([native])
        XCTAssertEqual(TickerDirectoryFilter.category(for: merged[0]), .crypto)
        XCTAssertTrue(merged[0].isCrypto)
    }

    func testAlternativeSortsKeepMissingQuotesAtEnd() {
        XCTAssertEqual(TickerDirectorySections(catalog: catalog, sort: .price).entries.map(\.symbol),
                       ["NVDA", "AAPL", "TSLA", "MU"])
        XCTAssertEqual(TickerDirectorySections(catalog: catalog, sort: .loss).entries.map(\.symbol),
                       ["NVDA", "AAPL", "TSLA", "MU"])
        XCTAssertEqual(TickerDirectorySections(catalog: catalog, sort: .gain).entries.map(\.symbol),
                       ["TSLA", "AAPL", "NVDA", "MU"])
        XCTAssertEqual(TickerDirectorySections(catalog: catalog, sort: .symbol).entries.map(\.symbol),
                       ["AAPL", "MU", "NVDA", "TSLA"])
    }
}
