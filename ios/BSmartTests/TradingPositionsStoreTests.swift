import XCTest
@testable import BSmart

@MainActor
final class TradingPositionsStoreTests: XCTestCase {
    func testTickerHoldingsUseLivePositionsAndPreserveVenueIdentity() async throws {
        let reader = BasicWalletTestReader()
        reader.rows = ["": [reader.position(coin: "ETH")],
                       "xyz": [reader.position(coin: "xyz:SNDK", size: "-0.011"),
                               reader.position(coin: "xyz:NVDA")]]
        let service = BasicWalletTestService()
        let store = TradingPositionsStore(service: service, reader: reader)
        await store.refresh(wallet: service.wallet)
        let positions = store.rows.filter { $0.matches(symbol: "sndk") }
        XCTAssertEqual(positions.map(\.coin), ["xyz:SNDK"])
        XCTAssertTrue(try XCTUnwrap(positions.first).quantity.isNegative)
        XCTAssertTrue(positions[0].matches(symbol: "xyz:SNDK"))
        XCTAssertFalse(positions[0].matches(symbol: "other:SNDK"))
        XCTAssertEqual(store.rows.filter { $0.matches(symbol: nil) }.count, 3)
        XCTAssertEqual(store.rows.filter { $0.matches(symbol: "ETH") }.count, 1)
        XCTAssertTrue(store.rows.filter { $0.matches(symbol: "BTC") }.isEmpty)
    }

    func testNativeAndHIP3PositionsUseExactDirectionAndDoNotMixMarkets() async throws {
        let reader = BasicWalletTestReader()
        reader.rows = ["": [reader.position(coin: "ETH", size: "1.5")], "xyz": [reader.position(coin: "xyz:NVDA", size: "-2")]]
        let service = BasicWalletTestService()
        let store = TradingPositionsStore(service: service, reader: reader)
        await store.refresh(wallet: service.wallet)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.rows.map(\.coin), ["ETH", "xyz:NVDA"])
        XCTAssertEqual(store.rows.last?.quantity.isNegative, true)
        XCTAssertEqual(store.rows.last?.symbol, "NVDA")
        XCTAssertEqual(store.rows.last?.entryPrice?.wire, "200")
    }

    func testVerifiedRegistrationAvoidsASecondAccountRequest() async throws {
        let service = BasicWalletTestService()
        let registration = try service.walletRegistration()
        let store = TradingPositionsStore(service: service, reader: BasicWalletTestReader())
        await store.refresh(wallet: service.wallet, verifiedRegistration: registration)
        XCTAssertTrue(store.didLoad)
        XCTAssertEqual(service.registrationReads, 1)
    }

    func testPositionRefreshShowsPartialResultsBeforeCompletion() async throws {
        let service = BasicWalletTestService()
        let reader = BasicWalletTestReader()
        reader.rows = ["xyz": [reader.position(coin: "xyz:NVDA")]]
        let store = TradingPositionsStore(service: service, reader: reader)
        var partialCounts: [Int] = []
        await store.refresh(wallet: service.wallet, onProgress: { partialCounts.append($0.count) })
        XCTAssertTrue(partialCounts.contains(1))
        XCTAssertEqual(store.rows.map(\.coin), ["xyz:NVDA"])
        XCTAssertTrue(store.didLoad)
    }

    func testWrongVerifiedRegistrationCannotReadAnotherWallet() async throws {
        let service = BasicWalletTestService()
        let wrong = TradingWalletRegistration(accountId: UUID(), address: service.wallet.address)
        let store = TradingPositionsStore(service: service, reader: BasicWalletTestReader())
        await store.refresh(wallet: service.wallet, verifiedRegistration: wrong)
        XCTAssertFalse(store.didLoad)
        XCTAssertNotNil(store.errorMessage)
    }

    func testPartialOutageIsVisibleAndCannotMasqueradeAsFlatAccount() async throws {
        let reader = BasicWalletTestReader(); reader.failDEX = "xyz"
        let service = BasicWalletTestService(), store = TradingPositionsStore(service: BasicWalletTestService(), reader: reader)
        // Each service uses the same public fixture account, never a device key.
        await store.refresh(wallet: service.wallet)
        XCTAssertNotNil(store.errorMessage)
        do { _ = try await HyperliquidFlatAccountCheck(reader: reader).check(owner: service.wallet.address); XCTFail("Missing venue accepted") }
        catch {}
    }

    func testIdentityChangeAndClearDiscardPositions() async throws {
        let reader = BasicWalletTestReader(), service = BasicWalletTestService()
        reader.afterRead = { service.walletAccountID = UUID() }
        let store = TradingPositionsStore(service: service, reader: reader)
        await store.refresh(wallet: service.wallet)
        XCTAssertTrue(store.rows.isEmpty)
        XCTAssertFalse(store.didLoad)
        store.clear()
        XCTAssertFalse(store.isLoading)
    }

    func testStaleWrongVenueDuplicateAndInvalidNumericPositionsAreRejected() throws {
        let reader = BasicWalletTestReader()
        for rows in [[reader.position(coin: "NVDA")], [reader.position(), reader.position()], [reader.position(size: "NaN")]] {
            let data = try reader.positionData(rows)
            XCTAssertThrowsError(try TradingPositionRow.decode(data, dex: "xyz"))
        }
        XCTAssertThrowsError(try TradingPositionRow.decode(reader.positionData([], at: Date().addingTimeInterval(-60)), dex: "xyz"))
    }

    func testPositionDisplaySymbolAndMarginReturn() throws {
        let position = TradingPositionRow(coin: "xyz:SNDK", dex: "xyz", quantity: try .init("0.006"),
            entryPrice: try .init("200"), unrealizedPnL: try .init("-0.12"), leverage: 10)
        XCTAssertEqual(position.symbol, "SNDK")
        XCTAssertEqual(try XCTUnwrap(position.returnPercent), -100, accuracy: 0.0001)
    }

    func testProfilePositionQuoteUsesExactMarketAndAbsoluteSize() async throws {
        let markets = try await DebugTradingMarketClient().fetchMarkets(
            dex: .init(name: "xyz", displayName: "XYZ"))
        let market = try XCTUnwrap(markets.first { $0.coin == "xyz:NVDA" })
        let position = TradingPositionRow(coin: "xyz:NVDA", dex: "xyz", quantity: try .init("-0.5"),
            entryPrice: try .init("190"), unrealizedPnL: try .init("-1"), leverage: 5)
        let quote = try XCTUnwrap(PortfolioPositionQuote(position: position, market: market))
        XCTAssertEqual(quote.marketValue, 100, accuracy: 0.001)
        XCTAssertEqual(quote.currentPrice, 200)
        let holding = PortfolioHoldingSnapshot(live: position, quote: quote)
        XCTAssertEqual(holding.quantity, 0.5)
        XCTAssertEqual(holding.value, 100)
        XCTAssertEqual(holding.averageCost, 190)
        XCTAssertEqual(holding.gain, -1)
        XCTAssertEqual(try XCTUnwrap(holding.gainPercent), -1 / 95, accuracy: 0.0001)

        let otherVenue = TradingPositionRow(coin: "test:NVDA", dex: "test", quantity: try .init("0.5"),
            entryPrice: nil, unrealizedPnL: try .init("0"), leverage: 5)
        XCTAssertNil(PortfolioPositionQuote(position: otherVenue, market: market))
    }

    func testFlatCheckRejectsAnyPositionOrOpenOrder() async throws {
        let reader = BasicWalletTestReader(), wallet = BasicWalletTestService().wallet
        _ = try await HyperliquidFlatAccountCheck(reader: reader).check(owner: wallet.address)
        reader.rows = ["xyz": [reader.position()]]
        do { _ = try await HyperliquidFlatAccountCheck(reader: reader).check(owner: wallet.address); XCTFail("Position ignored") } catch {}
        reader.rows = [:]; reader.hasOrder = true
        do { _ = try await HyperliquidFlatAccountCheck(reader: reader).check(owner: wallet.address); XCTFail("Open order ignored") } catch {}
    }
}

@MainActor
final class BasicWalletTestService: AccountWalletServicing {
    let wallet = HyperliquidTradingFixture.wallet
    var walletAccountID: UUID? = HyperliquidTradingFixture.wallet.accountID
    var registrationReads = 0
    func walletRegistration() throws -> TradingWalletRegistration {
        registrationReads += 1
        return .init(accountId: walletAccountID ?? UUID(), address: wallet.address)
    }
    func walletChallenge(address: String) throws -> TradingWalletChallenge { throw DeviceWalletError.invalidProof }
    func bindWallet(challenge: TradingWalletChallenge, signature: String) throws -> TradingWalletRegistration { throw DeviceWalletError.invalidProof }
    func fundingSigningLease(wallet: DeviceWalletSummary) throws -> FundingSigningLease {
        guard walletAccountID == wallet.accountID else { throw DeviceWalletError.accountChanged }
        return .init(wallet: wallet, expiresAt: Date().addingTimeInterval(60))
    }
}

@MainActor
final class BasicWalletTestReader: HyperliquidExecutionReading {
    var rows: [String: [[String: Any]]] = [:]
    var mode = "default"
    var failDEX: String?
    var hasOrder = false
    var afterRead: (() -> Void)?
    func position(coin: String = "xyz:NVDA", size: String = "1") -> [String: Any] {
        ["type": "oneWay", "position": ["coin": coin, "szi": size, "entryPx": "200", "unrealizedPnl": "-0.5", "leverage": ["value": 10]]]
    }
    func positionData(_ rows: [[String: Any]], at: Date = Date()) throws -> Data {
        try HyperliquidTradingFixture.data(["assetPositions": rows, "time": UInt64(at.timeIntervalSince1970 * 1000)])
    }
    func read(_ query: HyperliquidExecutionQuery) throws -> Data {
        defer { afterRead?() }
        switch query {
        case .dexs: return Data(#"[null,{"name":"xyz"}]"#.utf8)
        case .positions(_, let dex):
            if failDEX == dex { throw HyperliquidTradingCheckError.unavailable }
            return try positionData(rows[dex] ?? [])
        case .openOrders: return Data((hasOrder ? "[{}]" : "[]").utf8)
        case .mode: return try HyperliquidTradingFixture.data(mode)
        default: throw HyperliquidTradingCheckError.invalidResponse
        }
    }
}
