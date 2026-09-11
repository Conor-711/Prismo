import XCTest
@testable import BSmart

final class PaperTradingEngineTests: XCTestCase {
    @MainActor
    func testFreshPaperAccountStartsWithTenThousandDollars() {
        let engine = PaperTradingEngine(storage: MemoryPaperTradingStore())

        XCTAssertEqual(engine.account.initialBalance, 10_000)
        XCTAssertEqual(engine.account.availableBalance, 10_000)
        XCTAssertEqual(engine.account.equity, 10_000)
        XCTAssertTrue(engine.account.positions.isEmpty)
    }

    @MainActor
    func testOpeningLongReservesMarginAndLiveMarkUpdatesPnL() throws {
        let engine = PaperTradingEngine(storage: MemoryPaperTradingStore())
        let entry = market(mark: 100)

        let execution = try engine.placeMarketOrder(
            side: .long,
            margin: 1_000,
            leverage: 5,
            market: entry
        )

        XCTAssertEqual(execution.kind, .opened)
        XCTAssertEqual(execution.notional, 5_000, accuracy: 0.001)
        XCTAssertEqual(execution.fee, 2.25, accuracy: 0.001)
        XCTAssertEqual(engine.account.availableBalance, 8_997.75, accuracy: 0.001)
        XCTAssertEqual(engine.account.marginUsed, 1_000, accuracy: 0.001)

        engine.markToMarket(market(mark: 110))

        XCTAssertEqual(engine.account.unrealizedPnL, 500, accuracy: 0.001)
        XCTAssertEqual(engine.account.equity, 10_497.75, accuracy: 0.001)
    }

    @MainActor
    func testClosingPositionRealizesPnLAndReturnsCollateral() throws {
        let engine = PaperTradingEngine(storage: MemoryPaperTradingStore())
        try engine.placeMarketOrder(
            side: .long,
            margin: 1_000,
            leverage: 5,
            market: market(mark: 100)
        )
        engine.markToMarket(market(mark: 110))

        let close = try engine.closePosition(coin: "xyz:NVDA", market: market(mark: 110))

        XCTAssertEqual(close.kind, .closed)
        XCTAssertEqual(close.realizedPnL, 500, accuracy: 0.001)
        XCTAssertTrue(engine.account.positions.isEmpty)
        XCTAssertEqual(engine.account.realizedPnL, 500, accuracy: 0.001)
        XCTAssertEqual(engine.account.equity, 10_495.275, accuracy: 0.001)
    }

    @MainActor
    func testOppositeLargerOrderFlipsPosition() throws {
        let engine = PaperTradingEngine(storage: MemoryPaperTradingStore())
        let market = market(mark: 100)
        try engine.placeMarketOrder(side: .long, margin: 100, leverage: 2, market: market)

        let execution = try engine.placeMarketOrder(
            side: .short,
            margin: 200,
            leverage: 2,
            market: market
        )

        XCTAssertEqual(execution.kind, .flipped)
        XCTAssertEqual(engine.account.positions.count, 1)
        XCTAssertEqual(engine.account.positions[0].side, .short)
        XCTAssertEqual(engine.account.positions[0].size, 2, accuracy: 0.001)
    }

    @MainActor
    func testMarkCrossingMaintenanceThresholdLiquidatesIsolatedPosition() throws {
        let engine = PaperTradingEngine(storage: MemoryPaperTradingStore())
        try engine.placeMarketOrder(
            side: .long,
            margin: 100,
            leverage: 10,
            market: market(mark: 100)
        )

        engine.markToMarket(market(mark: 90))

        XCTAssertTrue(engine.account.positions.isEmpty)
        XCTAssertEqual(engine.latestLiquidation?.kind, .liquidated)
        XCTAssertEqual(engine.account.executions.first?.kind, .liquidated)
        XCTAssertGreaterThanOrEqual(engine.account.availableBalance, 0)
    }

    private func market(mark: Double) -> HyperliquidPerpMarket {
        HyperliquidPerpMarket(
            coin: "xyz:NVDA",
            symbol: "NVDA",
            dex: "xyz",
            dexDisplayName: "XYZ",
            sizeDecimals: 4,
            maxLeverage: 20,
            marginTableID: 20,
            isIsolatedOnly: false,
            isDelisted: false,
            markPrice: mark,
            midPrice: mark,
            oraclePrice: mark,
            previousDayPrice: 100,
            dayNotionalVolume: 50_000_000,
            openInterest: 100_000,
            fundingRate: 0,
            impactBidPrice: nil,
            impactAskPrice: nil,
            updatedAt: Date()
        )
    }
}

private final class MemoryPaperTradingStore: PaperTradingPersisting {
    private var value: PaperTradingAccount?

    func load() -> PaperTradingAccount? { value }
    func save(_ account: PaperTradingAccount) { value = account }
    func clear() { value = nil }
}
