import Foundation

struct AppTickerCatalogEntry: Identifiable, Hashable {
    let symbol: String
    var companyName: String
    var price: Double?
    var dayChange: Double?
    var venue: String?
    var isCrypto = false
    var volume24h: Double?
    var maxLeverage: Int?
    var id: String { symbol }

    static func merge(_ entries: [Self]) -> [Self] {
        var result: [String: Self] = [:]
        for entry in entries {
            let symbol = entry.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "$" )).uppercased()
            guard !symbol.isEmpty else { continue }
            let price = entry.price.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            var next = result[symbol] ?? Self(symbol: symbol, companyName: symbol)
            if !entry.companyName.isEmpty && entry.companyName.uppercased() != symbol {
                next.companyName = entry.companyName
            }
            if let price {
                next.price = price
                next.dayChange = entry.dayChange.flatMap { $0.isFinite ? $0 : nil }
                next.volume24h = entry.volume24h.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
                next.maxLeverage = entry.maxLeverage.flatMap { $0 > 0 ? $0 : nil }
                next.venue = entry.venue
                next.isCrypto = entry.isCrypto
            }
            result[symbol] = next
        }
        return result.values.sorted { $0.symbol < $1.symbol }
    }
}

extension AppModel {
    func tickerCatalog(markets: [HyperliquidPerpMarket]) -> [AppTickerCatalogEntry] {
        let accountSymbols = smartAccounts.flatMap { ($0.topTickers ?? []) + [$0.recentTicker].compactMap { $0 } }
        let symbols = accountSymbols + smartAccountUpdates.map(\.ticker)
            + smartMoneyMovements.map(\.ticker) + signals.map(\.ticker)
            + smartAccountEvidenceByAuthor.values.flatMap { $0.map(\.ticker) }
        var entries = symbols.map { AppTickerCatalogEntry(symbol: $0, companyName: $0) }
        entries += positions.map {
            AppTickerCatalogEntry(symbol: $0.ticker, companyName: $0.companyName, price: $0.currentPrice)
        }
        entries += intelligence.map {
            AppTickerCatalogEntry(symbol: $0.ticker, companyName: $0.companyName,
                                  price: $0.currentPrice, dayChange: $0.dayChangePercent)
        }
        // Higher-volume markets win duplicate symbols; preserve their venue with the quote.
        entries += markets.filter { !$0.isDelisted }.sorted { $0.dayNotionalVolume < $1.dayNotionalVolume }.map {
            AppTickerCatalogEntry(symbol: $0.symbol, companyName: $0.symbol,
                                  price: $0.markPrice, dayChange: $0.dayChangePercent, venue: $0.dexDisplayName,
                                  isCrypto: $0.dex.isEmpty,
                                  volume24h: $0.dayNotionalVolume, maxLeverage: $0.maxLeverage)
        }
        return AppTickerCatalogEntry.merge(entries)
    }
}
