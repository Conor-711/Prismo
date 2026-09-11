import Foundation

struct TickerDirectorySections {
    let trending: [AppTickerCatalogEntry]
    let remaining: [AppTickerCatalogEntry]
    var matchCount: Int { trending.count + remaining.count }

    init(catalog: [AppTickerCatalogEntry], trendingSymbols: [String], query: String = "") {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty {
            trending = []
            remaining = catalog.filter {
                $0.symbol.localizedCaseInsensitiveContains(search)
                    || $0.companyName.localizedCaseInsensitiveContains(search)
            }
            return
        }

        let entries = Dictionary(catalog.map { ($0.symbol, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        trending = trendingSymbols.compactMap { symbol in
            let key = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "$" )).uppercased()
            guard let entry = entries[key], seen.insert(key).inserted else { return nil }
            return entry
        }
        remaining = catalog.filter { !seen.contains($0.symbol) }
    }
}
