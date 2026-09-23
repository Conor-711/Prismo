import XCTest
@testable import BSmart

enum HyperliquidTradingFixture {
    static let wallet = HyperliquidOrderTestSupport.wallet
    static let now = Date(timeIntervalSince1970: 1_789_084_801)
    static let instant = ContinuousClock.now
    static let coin = "xyz:NVDA"

    static func data(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed, .sortedKeys])
    }

    static func metadata(collateral: Int = 0, mode: String? = nil) throws -> Data {
        var row: [String: Any] = ["name": coin, "szDecimals": 3, "maxLeverage": 20]
        if let mode { row["marginMode"] = mode }
        return try data(["collateralToken": collateral, "universe": [row]])
    }

    static func market(mode: String? = nil) throws -> HyperliquidExecutionMarket {
        try .resolve(perpDexs: HyperliquidOrderTestSupport.dexs, meta: metadata(mode: mode), dex: "xyz", coin: coin)
    }

    static func leverage(_ type: String = "cross", _ value: Int = 10, raw: String = "-95.059824") -> [String: Any] {
        var result: [String: Any] = ["type": type, "value": value]
        if type == "isolated" { result["rawUsd"] = raw }
        return result
    }

    static func active(buy: String = "8.123456789012345678", sell: String = "3.125",
                       leverage: [String: Any] = leverage(), overrides: [String: Any] = [:]) throws -> Data {
        var fields: [String: Any] = ["user": wallet.address, "coin": coin, "leverage": leverage,
            "maxTradeSzs": [buy, sell], "availableToTrade": ["180.001234567890123456", "60.0"], "markPx": "219.88"]
        fields.merge(overrides) { _, new in new }
        return try data(fields)
    }

    static func row(size: String = "-2.5", coin: String = coin,
                    leverage: [String: Any] = leverage()) -> [String: Any] {
        ["type": "oneWay", "position": ["coin": coin, "szi": size, "leverage": leverage]]
    }

    static func positions(rows: [[String: Any]] = [], at: Date = now) throws -> Data {
        try data(["time": UInt64(at.timeIntervalSince1970 * 1000), "assetPositions": rows,
                  "withdrawable": "0.0"])
    }

    static func responses(mode: HyperCoreAccountMode = .unifiedAccount, positionRows: [[String: Any]] = []) throws -> [Data] {
        try [HyperliquidOrderTestSupport.dexs, metadata(), data(mode.rawValue), active(),
             positions(rows: positionRows), active(), positions(rows: positionRows), data(mode.rawValue)]
    }

    static func snapshot(active: Data? = nil, positions: Data? = nil,
                         clock: TradingCheckClock = .init()) throws -> HyperliquidTradingSnapshot {
        let market = try market()
        return try .init(accountID: wallet.accountID, owner: wallet.address, market: market, mode: .unifiedAccount,
            active: .decode(active ?? Self.active(), owner: wallet.address, market: market),
            positions: .decode(positions ?? Self.positions(), market: market, now: clock.now),
            requestedAt: clock.now, checkedAt: clock.now,
            requestedContinuousAt: clock.instant, checkedContinuousAt: clock.instant)
    }

    static func order(side: HyperliquidOrderIntent.Side = .buy, size: String = "2.5", reduceOnly: Bool = false,
                      wallet: DeviceWalletSummary = wallet, nonce: UInt64 = 1_789_084_800_001,
                      expiry: UInt64 = 1_789_084_830_001, market: HyperliquidExecutionMarket? = nil) throws -> HyperliquidOrderIntent {
        try .init(wallet: wallet, market: market ?? Self.market(), side: side, size: size, limitPrice: "220",
                  reduceOnly: reduceOnly, cloid: "0x00000000000000000000000000000001", nonce: nonce, expiresAfter: expiry)
    }
}

final class TradingCheckClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = HyperliquidTradingFixture.now
    private var point = HyperliquidTradingFixture.instant
    var now: Date { lock.withLock { date } }
    var instant: ContinuousClock.Instant { lock.withLock { point } }
    func advance(wall: TimeInterval = 0, steady: Duration = .zero) {
        lock.withLock { date.addTimeInterval(wall); point = point.advanced(by: steady) }
    }
}

actor TradingCheckReaderStub: HyperliquidExecutionReading {
    let responses: [Data]
    let onRead: @Sendable (Int) throws -> Void
    private(set) var queries: [HyperliquidExecutionQuery] = []
    private var snapshotResponses = false
    private var previewResponses = false
    init(_ responses: [Data], onRead: @escaping @Sendable (Int) throws -> Void = { _ in }) {
        self.responses = responses; self.onRead = onRead
    }
    init(snapshot responses: [Data], onRead: @escaping @Sendable (Int) throws -> Void = { _ in }) {
        self.responses = responses; self.onRead = onRead; snapshotResponses = true
    }
    init(preview responses: [Data], onRead: @escaping @Sendable (Int) throws -> Void = { _ in }) {
        self.responses = responses; self.onRead = onRead; previewResponses = true
    }
    func read(_ query: HyperliquidExecutionQuery) async throws -> Data {
        let index: Int
        if snapshotResponses {
            let occurrence = queries.filter { $0 == query }.count
            switch query {
            case .dexs: index = 0
            case .metadata: index = 1
            case .mode: index = occurrence == 0 ? 2 : 7
            case .active: index = occurrence == 0 ? 3 : 5
            case .positions: index = occurrence == 0 ? 4 : 6
            default: throw HyperliquidTradingCheckError.invalidResponse
            }
        } else if previewResponses {
            switch query {
            case .fees: index = 0
            case .builderApproval: index = 1
            case .book: index = responses.count > 2 ? 2 : 1
            default: throw HyperliquidTradingCheckError.invalidResponse
            }
        } else { index = queries.count }
        queries.append(query)
        try onRead(index)
        guard responses.indices.contains(index) else { throw HyperliquidTradingCheckError.unavailable }
        return responses[index]
    }
}
