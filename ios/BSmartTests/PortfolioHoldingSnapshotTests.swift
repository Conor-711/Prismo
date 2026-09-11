import XCTest
@testable import BSmart

final class PortfolioHoldingSnapshotTests: XCTestCase {
    func testExternalHoldingUsesOwnPriceAndCostForValueAndReturn() {
        let position = PortfolioPosition(id: UUID(), ticker: "NVDA", companyName: "NVIDIA",
                                         shares: 10, averageCost: 100, currentPrice: 120)
        let holding = PortfolioHoldingSnapshot(external: position)
        XCTAssertEqual(holding.price, 120)
        XCTAssertEqual(holding.averageCost, 100)
        XCTAssertEqual(holding.value, 1200)
        XCTAssertEqual(holding.gain, 200)
        XCTAssertEqual(holding.gainPercent, 0.2)
        XCTAssertNil(holding.leverage)
    }

    func testIncompleteHoldingsNeverInventValueOrReturns() {
        var position = PortfolioPosition(id: UUID(), ticker: "NVDA", companyName: "NVIDIA",
                                        shares: 10, averageCost: 0, currentPrice: 120)
        let noCost = PortfolioHoldingSnapshot(external: position)
        XCTAssertEqual(noCost.value, 1200)
        XCTAssertNil(noCost.gain)
        XCTAssertNil(noCost.gainPercent)
        position.currentPrice = .nan
        let noQuote = PortfolioHoldingSnapshot(external: position)
        XCTAssertNil(noQuote.value)
        XCTAssertNil(noQuote.price)
        position.currentPrice = 120
        position.averageCost = 100
        position.shares = 0
        let noQuantity = PortfolioHoldingSnapshot(external: position)
        XCTAssertNil(noQuantity.value)
        XCTAssertNil(noQuantity.gainPercent)
    }

    func testAppEquityExcludesLeveragedNotionalAndRespectsShortDirection() {
        let now = Date()
        let position = PaperTradingPosition(id: UUID(), coin: "xyz:NVDA", symbol: "NVDA",
            dexDisplayName: "XYZ", side: .short, size: 10, entryPrice: 100, lastMarkPrice: 90,
            leverage: 5, maxLeverage: 20, isolatedMargin: 200, fundingPnL: 0,
            lastFundingAt: now, openedAt: now, updatedAt: now)
        let holding = PortfolioHoldingSnapshot(inApp: position)
        XCTAssertEqual(holding.value, 900)
        XCTAssertEqual(holding.gain, 100)
        XCTAssertEqual(holding.gainPercent, 0.5)
        var account = PaperTradingAccount.fresh(now: now)
        account.availableBalance = 800
        account.positions = [position]
        XCTAssertEqual(account.equity, 1100)
        XCTAssertNotEqual(account.equity, account.availableBalance + (holding.value ?? 0))
    }
}
