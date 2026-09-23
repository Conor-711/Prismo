import Foundation

enum TickerDirectoryFilter: String, CaseIterable, Identifiable {
    case all, crypto, stocks, commodities, indices, forex

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .crypto: "Crypto"
        case .stocks: "Stocks"
        case .commodities: "Commodities"
        case .indices: "Indices"
        case .forex: "FX"
        }
    }

    private static let commoditySymbols: Set<String> = [
        "ALUMINIUM", "BRENTOIL", "CL", "COPPER", "CORN", "GOLD", "NATGAS",
        "PALLADIUM", "PLATINUM", "SILVER", "TTF", "URANIUM", "WHEAT", "WTI"
    ]
    private static let indexSymbols: Set<String> = [
        "DXY", "HSI", "IBOV", "JP225", "KR200", "NIFTY", "SP500",
        "USTECH", "VIX", "VOL", "XYZ100"
    ]
    private static let forexSymbols: Set<String> = [
        "AUD", "CAD", "CHF", "EUR", "EURUSD", "GBP", "GBPUSD", "JPY",
        "KRW", "USDJPY"
    ]

    static func category(for entry: AppTickerCatalogEntry) -> Self {
        if entry.isCrypto { return .crypto }
        if commoditySymbols.contains(entry.symbol) { return .commodities }
        if indexSymbols.contains(entry.symbol) { return .indices }
        if forexSymbols.contains(entry.symbol) { return .forex }
        return .stocks
    }
}

enum TickerDirectorySort: String, CaseIterable, Identifiable {
    case volume, gain, loss, price, symbol

    var id: Self { self }

    var title: String {
        switch self {
        case .volume: "Volume"
        case .gain: "Top gainers"
        case .loss: "Top losers"
        case .price: "Price"
        case .symbol: "A-Z"
        }
    }
}

struct TickerDirectorySections {
    let entries: [AppTickerCatalogEntry]

    init(catalog: [AppTickerCatalogEntry], query: String = "",
         filter: TickerDirectoryFilter = .all, sort: TickerDirectorySort = .volume) {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = catalog.filter { entry in
            let matchesSearch = search.isEmpty || entry.symbol.localizedCaseInsensitiveContains(search)
                || entry.companyName.localizedCaseInsensitiveContains(search)
            guard matchesSearch else { return false }
            return filter == .all || TickerDirectoryFilter.category(for: entry) == filter
        }
        entries = filtered.sorted { left, right in
            let leftValue: Double?
            let rightValue: Double?
            switch sort {
            case .volume:
                leftValue = left.volume24h
                rightValue = right.volume24h
            case .gain, .loss:
                leftValue = left.dayChange
                rightValue = right.dayChange
            case .price:
                leftValue = left.price
                rightValue = right.price
            case .symbol:
                return left.symbol < right.symbol
            }
            if leftValue == nil { return rightValue == nil && left.symbol < right.symbol }
            guard let rightValue, let leftValue else { return true }
            if leftValue == rightValue { return left.symbol < right.symbol }
            return sort == .loss ? leftValue < rightValue : leftValue > rightValue
        }
    }
}
