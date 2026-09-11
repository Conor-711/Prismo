import XCTest
@testable import BSmart

final class AppTickerCatalogTests: XCTestCase {
    func testCatalogNormalizesAndDeduplicatesWithoutLosingCompanyName() {
        let items = AppTickerCatalogEntry.merge([
            .init(symbol: " nvda ", companyName: "NVIDIA", price: 100),
            .init(symbol: "$NVDA", companyName: "NVDA", price: 200, dayChange: 0.03, venue: "XYZ"),
            .init(symbol: "mstr", companyName: "Strategy"),
            .init(symbol: "", companyName: "")
        ])
        XCTAssertEqual(items.map(\.symbol), ["MSTR", "NVDA"])
        XCTAssertEqual(items[1].companyName, "NVIDIA")
        XCTAssertEqual(items[1].price, 200)
        XCTAssertEqual(items[1].venue, "XYZ")
        XCTAssertEqual(items[1].dayChange, 0.03)
        XCTAssertNil(items[0].price)
    }

    func testMissingAndInvalidQuotesNeverBecomeZeroPrices() {
        let items = AppTickerCatalogEntry.merge([
            .init(symbol: "MU", companyName: "Micron", price: 0, dayChange: 0),
            .init(symbol: "SNDK", companyName: "SanDisk", price: .nan),
            .init(symbol: "MU", companyName: "MU", price: -1)
        ])
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.price == nil && $0.dayChange == nil })
    }

    func testVolumeAndChangeStayWithWinningQuote() {
        let items = AppTickerCatalogEntry.merge([
            .init(symbol: "NVDA", companyName: "NVIDIA", price: 100, dayChange: 0.01,
                  venue: "A", volume24h: 100, maxLeverage: 5),
            .init(symbol: "NVDA", companyName: "NVDA", price: 102, dayChange: -0.02,
                  venue: "B", volume24h: 200, maxLeverage: 10),
            .init(symbol: "NVDA", companyName: "NVDA", price: .nan, venue: "C", volume24h: 900)
        ])
        XCTAssertEqual(items.first?.volume24h, 200)
        XCTAssertEqual(items.first?.dayChange, -0.02)
        XCTAssertEqual(items.first?.venue, "B")
        XCTAssertEqual(items.first?.maxLeverage, 10)
    }

    func testMissingVolumeNeverInheritsAnotherVenueOrInventsDailyChange() {
        let item = AppTickerCatalogEntry.merge([
            .init(symbol: "MU", companyName: "Micron", price: 100, dayChange: 0.1,
                  venue: "A", volume24h: 500),
            .init(symbol: "MU", companyName: "MU", price: 110)
        ])[0]
        XCTAssertNil(item.volume24h)
        XCTAssertNil(item.dayChange)
        XCTAssertNil(item.venue)
    }

    func testDollarFormatHasNoCurrencyCodeOrUSPrefix() {
        XCTAssertEqual(1234.5.formatted(.bSmartDollars.precision(.fractionLength(2))), "$1,234.50")
        XCTAssertEqual((-12.5).formatted(.bSmartDollars.precision(.fractionLength(2))), "-$12.50")
        XCTAssertEqual(12.5.formatted(.bSmartDollars.precision(.fractionLength(2))
            .sign(strategy: .always())), "+$12.50")
    }
}
