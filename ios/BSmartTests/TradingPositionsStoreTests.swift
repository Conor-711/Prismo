import XCTest
@testable import BSmart

@MainActor
final class TradingPositionsStoreTests: XCTestCase {
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
    func walletRegistration() throws -> TradingWalletRegistration { .init(accountId: walletAccountID ?? UUID(), address: wallet.address) }
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
