import XCTest
import UIKit
@testable import BSmart

final class OpinionTraderDemoTests: XCTestCase {
    func testDistinctPeopleChronologyAndPositionFigures() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let data = OpinionTraderDemoData(ticker: "nvda", referencePrice: 180, now: now)
        XCTAssertEqual(data.ticker, "NVDA")
        XCTAssertEqual(data.totalTraders, 8)
        XCTAssertEqual(data.traders.count, 6)
        XCTAssertEqual(Set(data.traders.map(\.nickname)).count, 6)
        XCTAssertEqual(Set(data.traders.map(\.avatarAsset)).count, 6)
        for index in data.traders.indices {
            let row = data.traders[index]
            XCTAssertGreaterThan(row.entryPrice, 0)
            XCTAssertGreaterThan(row.notionalUSD, 0)
            XCTAssertGreaterThan(row.leverage, 0)
            XCTAssertLessThan(row.openedAt, now)
            XCTAssertNotNil(UIImage(named: row.avatarAsset))
            if index > 0 { XCTAssertLessThan(row.openedAt, data.traders[index - 1].openedAt) }
        }
    }

    func testMissingOrInvalidReferenceStillHasValidIllustrativePrices() {
        for price in [nil, Double.nan, .infinity, -1, 0] as [Double?] {
            let data = OpinionTraderDemoData(ticker: "MU", referencePrice: price, now: Date())
            XCTAssertTrue(data.traders.allSatisfy { $0.entryPrice.isFinite && $0.entryPrice > 0 })
        }
    }
}
