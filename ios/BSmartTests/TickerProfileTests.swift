import XCTest
@testable import BSmart

final class TickerProfileTests: XCTestCase {
    func testMajorActivityTickersHaveBilingualSourcedProfilesOffline() throws {
        let symbols = ["NVDA", "MSTR", "HOOD", "PLTR", "MU", "SNDK", "TSLA", "AMD", "AAPL",
                       "MSFT", "AMZN", "ASTS", "NBIS", "IREN", "MRNA", "FCEL", "GME", "META",
                       "MRVL", "CLMT", "SNOW", "TEM", "AVGO", "CIFR", "INTC", "IONQ", "AAOI",
                       "HROW", "QQQ", "TQQQ", "XLK", "GOOGL", "GOOG", "NFLX", "COIN", "CRCL",
                       "CRWV", "APP", "ARM", "CRWD", "LITE", "ORCL", "SMCI", "SOFI", "RDDT", "TSM", "SMH"]
        for symbol in symbols {
            let profile = try XCTUnwrap(TickerProfile.lookup(symbol), symbol)
            XCTAssertFalse(profile.english.isEmpty, symbol)
            XCTAssertFalse(profile.chinese.isEmpty, symbol)
            XCTAssertEqual(profile.source?.scheme, "https", symbol)
            XCTAssertNotNil(profile.source?.host, symbol)
        }
        XCTAssertEqual(TickerProfile.lookup(" nbis ")?.name, "Nebius")
        XCTAssertNil(TickerProfile.lookup("NOT_A_REAL_SYMBOL"))
        XCTAssertEqual(TickerProfile.lookup("CIFR")?.name, "Cipher Digital")
        XCTAssertEqual(TickerProfile.lookup("TQQQ")?.category, "Leveraged ETF")
        XCTAssertTrue(TickerProfile.lookup("TQQQ")!.english.contains("daily"))
    }

    @MainActor
    func testWatchlistActionPersistsWithoutOverwritingHoldings() async throws {
        let suite = "BSmartTests.TickerFollow.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(client: BundleBSmartAPIClient(), defaults: defaults)
        await model.load()
        let history = model.portfolioHistory
        model.setTickerFollowed(true, ticker: " newticker ", companyName: "New ticker")
        model.setTickerFollowed(true, ticker: "NEWTICKER", companyName: "New ticker")
        XCTAssertEqual(model.positions.filter { $0.ticker == "NEWTICKER" }.count, 1)
        XCTAssertFalse(try XCTUnwrap(model.position(for: "NEWTICKER")).isPosition)
        XCTAssertEqual(model.portfolioHistory, history)
        let restored = AppModel(client: BundleBSmartAPIClient(), defaults: defaults)
        await restored.load()
        XCTAssertNotNil(restored.position(for: "NEWTICKER"))
        model.setTickerFollowed(false, ticker: "NEWTICKER", companyName: "New ticker")
        XCTAssertNil(model.position(for: "NEWTICKER"))
        model.addPosition(ticker: "NEWTICKER", companyName: "New ticker", shares: 10, averageCost: 120)
        let holding = try XCTUnwrap(model.position(for: "NEWTICKER"))
        model.setTickerFollowed(true, ticker: "NEWTICKER", companyName: "New ticker")
        model.setTickerFollowed(false, ticker: "NEWTICKER", companyName: "New ticker")
        XCTAssertEqual(model.position(for: "NEWTICKER"), holding)
    }
}
