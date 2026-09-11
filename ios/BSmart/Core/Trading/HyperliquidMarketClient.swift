import Foundation

protocol HyperliquidMarketDataClient: Sendable {
    func fetchDexs() async throws -> [HyperliquidDex]
    func fetchMarkets(dex: HyperliquidDex) async throws -> [HyperliquidPerpMarket]
    func fetchCandles(
        coin: String,
        interval: String,
        start: Date,
        end: Date
    ) async throws -> [HyperliquidCandle]
}

enum HyperliquidMarketDataError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case malformedMarketData
    case marketUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Hyperliquid returned an invalid response.".bSmartLocalized
        case let .httpStatus(status):
            "Hyperliquid request failed with status %d.".bSmartLocalized(status)
        case .malformedMarketData:
            "Hyperliquid market metadata and prices did not align.".bSmartLocalized
        case let .marketUnavailable(symbol):
            "No active Hyperliquid market was found for %@.".bSmartLocalized(symbol)
        }
    }
}

actor HTTPHyperliquidMarketDataClient: HyperliquidMarketDataClient {
    static let mainnetInfoURL = URL(string: "https://api.hyperliquid.xyz/info")!

    private let infoURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(
        infoURL: URL = HTTPHyperliquidMarketDataClient.mainnetInfoURL,
        session: URLSession = .shared
    ) {
        self.infoURL = infoURL
        self.session = session
    }

    func fetchDexs() async throws -> [HyperliquidDex] {
        let response: [DexDTO?] = try await request(["type": "perpDexs"])
        var dexs = [HyperliquidDex(name: "", displayName: "Hyperliquid")]
        dexs.append(contentsOf: response.compactMap { item in
            guard let item, !item.name.isEmpty else { return nil }
            return HyperliquidDex(
                name: item.name,
                displayName: item.fullName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                    ?? item.name.uppercased()
            )
        })
        return dexs.reduce(into: []) { result, dex in
            guard !result.contains(where: { $0.id == dex.id }) else { return }
            result.append(dex)
        }
    }

    func fetchMarkets(dex: HyperliquidDex) async throws -> [HyperliquidPerpMarket] {
        var body: [String: Any] = ["type": "metaAndAssetCtxs"]
        if !dex.name.isEmpty {
            body["dex"] = dex.name
        }
        let response: MetaAndContextsDTO = try await request(body)
        guard response.meta.universe.count == response.contexts.count else {
            throw HyperliquidMarketDataError.malformedMarketData
        }
        let now = Date()
        return zip(response.meta.universe, response.contexts).compactMap { asset, context in
            guard let markPrice = context.markPx.doubleValue,
                  let oraclePrice = context.oraclePx.doubleValue,
                  let previousDayPrice = context.prevDayPx.doubleValue
            else { return nil }

            let symbol = asset.name.split(separator: ":").last.map(String.init) ?? asset.name
            return HyperliquidPerpMarket(
                coin: asset.name,
                symbol: symbol,
                dex: dex.name,
                dexDisplayName: dex.displayName,
                sizeDecimals: asset.szDecimals,
                maxLeverage: max(1, asset.maxLeverage),
                marginTableID: asset.marginTableId,
                isIsolatedOnly: asset.onlyIsolated ?? false,
                isDelisted: asset.isDelisted ?? false,
                markPrice: markPrice,
                midPrice: context.midPx?.doubleValue,
                oraclePrice: oraclePrice,
                previousDayPrice: previousDayPrice,
                dayNotionalVolume: context.dayNtlVlm.doubleValue ?? 0,
                openInterest: context.openInterest.doubleValue ?? 0,
                fundingRate: context.funding.doubleValue ?? 0,
                impactBidPrice: context.impactPxs?.first?.doubleValue,
                impactAskPrice: context.impactPxs?.dropFirst().first?.doubleValue,
                updatedAt: now
            )
        }
    }

    func fetchCandles(
        coin: String,
        interval: String,
        start: Date,
        end: Date
    ) async throws -> [HyperliquidCandle] {
        let response: [CandleDTO] = try await request([
            "type": "candleSnapshot",
            "req": [
                "coin": coin,
                "interval": interval,
                "startTime": Int64(start.timeIntervalSince1970 * 1_000),
                "endTime": Int64(end.timeIntervalSince1970 * 1_000),
            ],
        ])
        return response.compactMap { candle in
            guard let open = candle.o.doubleValue,
                  let high = candle.h.doubleValue,
                  let low = candle.l.doubleValue,
                  let close = candle.c.doubleValue
            else { return nil }
            return HyperliquidCandle(
                openTime: Date(timeIntervalSince1970: Double(candle.t) / 1_000),
                closeTime: Date(timeIntervalSince1970: Double(candle.T) / 1_000),
                coin: candle.s,
                interval: candle.i,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: candle.v.doubleValue ?? 0,
                tradeCount: candle.n
            )
        }
        .sorted { $0.openTime < $1.openTime }
    }

    private func request<Response: Decodable>(_ body: [String: Any]) async throws -> Response {
        var request = URLRequest(url: infoURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw HyperliquidMarketDataError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw HyperliquidMarketDataError.httpStatus(response.statusCode)
        }
        return try decoder.decode(Response.self, from: data)
    }
}

@MainActor
final class HyperliquidTradingStore: ObservableObject {
    @Published private(set) var activeMarket: HyperliquidPerpMarket?
    @Published private(set) var candles: [HyperliquidCandle] = []
    @Published private(set) var marketCatalog: [HyperliquidPerpMarket] = []
    @Published private(set) var isLoadingMarket = false
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var errorMessage: String?
    @Published var chartRange: HyperliquidChartRange = .oneDay
    @Published var chartStyle: HyperliquidChartStyle = .line
    @Published private(set) var isLoadingCandles = false
    private var candleRequestID = UUID()
    private var marketRequestID = UUID()
    private var lastCandleRefresh: Date = .distantPast
    private let candleWindow: HyperliquidCandleWindow?

    private let client: HyperliquidMarketDataClient
    private var preferredDexCache: [HyperliquidPerpMarket] = []
    private var activeSymbol = ""

    init(client: HyperliquidMarketDataClient, candleWindow: HyperliquidCandleWindow? = nil) {
        self.client = client
        self.candleWindow = candleWindow
    }

    func makeSession(candleWindow: HyperliquidCandleWindow? = nil) -> HyperliquidTradingStore {
        HyperliquidTradingStore(client: client, candleWindow: candleWindow)
    }

    /// An explicit Feed market must never be replaced by the preferred ticker venue.
    func freshMarket(coin: String, symbol: String) async throws -> HyperliquidPerpMarket {
        let dexName = coin.contains(":") ? String(coin.split(separator: ":", maxSplits: 1)[0]) : ""
        let markets = try await client.fetchMarkets(dex: .init(name: dexName, displayName: dexName.uppercased()))
        try Task.checkCancellation()
        guard let market = markets.first(where: { $0.coin == coin }),
              market.symbol.caseInsensitiveCompare(symbol) == .orderedSame, !market.isDelisted,
              TradeAmountInput.quoteIsCurrent(market.updatedAt) else {
            throw HyperliquidMarketDataError.marketUnavailable(symbol)
        }
        return market
    }

    func market(for symbol: String) -> HyperliquidPerpMarket? {
        if let activeMarket, activeMarket.symbol.caseInsensitiveCompare(symbol) == .orderedSame {
            return activeMarket
        }
        let candidates = marketCatalog.filter { $0.dex == "xyz" }
        return preferredMarket(symbol: symbol, from: candidates)
            ?? preferredMarket(symbol: symbol, from: marketCatalog)
    }

    func runLiveMarket(symbol: String) async {
        let normalizedSymbol = symbol.uppercased()
        if activeSymbol != normalizedSymbol {
            candleRequestID = UUID()
            isLoadingCandles = false
            activeMarket = nil
            candles = []
            errorMessage = nil
        }
        activeSymbol = normalizedSymbol
        await loadInitialMarket(symbol: activeSymbol)

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            if activeMarket == nil {
                await loadInitialMarket(symbol: activeSymbol)
            } else {
                await refreshActiveMarket()
                if !Task.isCancelled, !isLoadingCandles,
                   Date().timeIntervalSince(lastCandleRefresh) >= 30 {
                    await reloadCandles()
                }
            }
        }
    }

    func reloadCandles() async {
        guard let market = activeMarket else { return }
        let requestID = UUID()
        candleRequestID = requestID
        let range = chartRange
        let window = candleWindow ?? HyperliquidCandleWindow(duration: range.duration, interval: range.candleInterval)
        if candles.first?.coin != market.coin || candles.first?.interval != window.interval {
            candles = []
        }
        isLoadingCandles = true
        defer { if candleRequestID == requestID { isLoadingCandles = false } }
        let end = Date()
        let start = end.addingTimeInterval(-window.duration)
        do {
            let fetched = try await client.fetchCandles(
                coin: market.coin,
                interval: window.interval,
                start: start,
                end: end
            )
            guard !Task.isCancelled, candleRequestID == requestID,
                  activeMarket?.coin == market.coin, chartRange == range else { return }
            candles = HyperliquidCandle.validated(fetched, coin: market.coin, interval: window.interval,
                                                 start: start, end: end)
            lastCandleRefresh = end
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, candleRequestID == requestID else { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadFullCatalog() async {
        guard !isLoadingCatalog else { return }
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        do {
            let dexs = try await client.fetchDexs()
            let marketClient = client
            let markets = await withTaskGroup(of: [HyperliquidPerpMarket].self) { group in
                for dex in dexs {
                    group.addTask {
                        (try? await marketClient.fetchMarkets(dex: dex)) ?? []
                    }
                }

                var catalog: [HyperliquidPerpMarket] = []
                for await batch in group {
                    catalog.append(contentsOf: batch)
                }
                return catalog
            }
            marketCatalog = markets
                .filter { !$0.isDelisted && $0.markPrice > 0 }
                .sorted { lhs, rhs in
                    if lhs.dayNotionalVolume != rhs.dayNotionalVolume {
                        return lhs.dayNotionalVolume > rhs.dayNotionalVolume
                    }
                    return lhs.coin < rhs.coin
                }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectMarket(_ market: HyperliquidPerpMarket) async {
        marketRequestID = UUID()
        isLoadingMarket = false
        activeSymbol = market.symbol.uppercased()
        activeMarket = market
        await reloadCandles()
    }

    private func loadInitialMarket(symbol: String) async {
        let requestID = UUID()
        marketRequestID = requestID
        isLoadingMarket = true
        defer { if marketRequestID == requestID { isLoadingMarket = false } }
        do {
            let preferred = (try? await client.fetchMarkets(
                dex: HyperliquidDex(name: "xyz", displayName: "XYZ")
            )) ?? []
            guard !Task.isCancelled, marketRequestID == requestID else { return }
            preferredDexCache = preferred
            mergeMarkets(preferred)
            var resolved = preferredMarket(symbol: symbol, from: preferredDexCache)
            if resolved == nil {
                await loadFullCatalog()
                guard !Task.isCancelled, marketRequestID == requestID else { return }
                resolved = preferredMarket(symbol: symbol, from: marketCatalog)
            }
            guard let market = resolved else {
                throw HyperliquidMarketDataError.marketUnavailable(symbol)
            }
            activeMarket = market
            errorMessage = nil
            await reloadCandles()
        } catch {
            guard !Task.isCancelled, marketRequestID == requestID else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func refreshActiveMarket() async {
        guard let current = activeMarket else { return }
        let dex = HyperliquidDex(name: current.dex, displayName: current.dexDisplayName)
        do {
            let markets = try await client.fetchMarkets(dex: dex)
            guard !Task.isCancelled, activeMarket?.coin == current.coin,
                  let refreshed = markets.first(where: { $0.coin == current.coin })
            else { return }
            mergeMarkets(markets)
            activeMarket = refreshed
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, activeMarket?.coin == current.coin else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func mergeMarkets(_ markets: [HyperliquidPerpMarket]) {
        var byCoin = Dictionary(marketCatalog.map { ($0.coin, $0) }, uniquingKeysWith: { _, last in last })
        for market in markets { byCoin[market.coin] = market }
        marketCatalog = byCoin.values.sorted { $0.coin < $1.coin }
    }

    private func preferredMarket(
        symbol: String,
        from markets: [HyperliquidPerpMarket]
    ) -> HyperliquidPerpMarket? {
        markets
            .filter { !$0.isDelisted && $0.markPrice > 0 && $0.symbol.caseInsensitiveCompare(symbol) == .orderedSame }
            .max { $0.dayNotionalVolume < $1.dayNotionalVolume }
    }
}

private struct DexDTO: Decodable {
    let name: String
    let fullName: String?
}

private struct MetaAndContextsDTO: Decodable {
    let meta: MetaDTO
    let contexts: [AssetContextDTO]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        meta = try container.decode(MetaDTO.self)
        contexts = try container.decode([AssetContextDTO].self)
    }
}

private struct MetaDTO: Decodable {
    let universe: [AssetDTO]
}

private struct AssetDTO: Decodable {
    let szDecimals: Int
    let name: String
    let maxLeverage: Int
    let marginTableId: Int?
    let onlyIsolated: Bool?
    let isDelisted: Bool?
}

private struct AssetContextDTO: Decodable {
    let funding: String
    let openInterest: String
    let prevDayPx: String
    let dayNtlVlm: String
    let oraclePx: String
    let markPx: String
    let midPx: String?
    let impactPxs: [String]?
}

private struct CandleDTO: Decodable {
    let t: Int64
    let T: Int64
    let s: String
    let i: String
    let o: String
    let c: String
    let h: String
    let l: String
    let v: String
    let n: Int
}

private extension String {
    var doubleValue: Double? {
        guard let value = Double(self), value.isFinite else { return nil }
        return value
    }

    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
