import Foundation

enum AppSearchCategory: String, CaseIterable, Identifiable {
    case all, tickers, opinions, authors, users
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .tickers: "Tickers"
        case .opinions: "Views"
        case .authors: "Authors"
        case .users: "Users"
        }
    }
}

enum AppSearchItem: Hashable, Identifiable {
    case ticker(AppTickerCatalogEntry)
    case opinion(SmartAccountUpdate)
    case movement(SmartMoneyMovement)
    case author(SmartAccountProfile)
    case money(SmartMoneySignal)
    case user(FeedPublicProfile)

    var id: String {
        switch self {
        case .ticker(let value): "ticker:\(value.symbol)"
        case .opinion(let value): "opinion:\(value.id)"
        case .movement(let value): "movement:\(value.id)"
        case .author(let value): "author:\(value.platform):\(value.id)"
        case .money(let value): "money:\(value.id)"
        case .user(let value): "user:\(value.id)"
        }
    }
    var category: AppSearchCategory {
        switch self {
        case .ticker: .tickers
        case .opinion, .movement: .opinions
        case .author, .money: .authors
        case .user: .users
        }
    }
    var title: String {
        switch self {
        case .ticker(let value): value.symbol
        case .opinion(let value): value.authorName
        case .movement(let value): value.publicIdentity.displayName
        case .author(let value): value.name
        case .money(let value): value.publicIdentity.displayName
        case .user(let value): value.nickname
        }
    }
    var investorRanking: String? {
        switch self {
        case .author(let value):
            if let percentile = value.platformPercentile, percentile.isFinite, (0...1).contains(percentile) {
                return "Top %d%%".bSmartLocalized(max(1, Int(ceil(percentile * 100))))
            }
            return value.resolvedRank > 0 ? "#\(value.resolvedRank)" : nil
        case .money(let value):
            return value.rank.flatMap { $0 > 0 ? "#\($0)" : nil }
        default: return nil
        }
    }
    var date: Date {
        switch self {
        case .opinion(let value): value.publishedAt
        case .movement(let value): value.observedAt
        default: .distantPast
        }
    }
    var ticker: String? {
        switch self {
        case .ticker(let value): value.symbol
        case .opinion(let value): value.ticker
        case .movement(let value): value.ticker
        default: nil
        }
    }
}

struct AppSearchQuery {
    let text: String
    let terms: [String]
    init(_ raw: String) {
        text = raw.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@$#")).trimmingCharacters(in: .whitespacesAndNewlines)
        terms = Self.fold(text).split(whereSeparator: \.isWhitespace).map(String.init)
    }
    static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                      locale: Locale(identifier: "en_US_POSIX")).lowercased()
    }
    static func aliases(_ symbol: String) -> String {
        switch symbol.uppercased() {
        case "BTC": "Bitcoin 比特币"
        case "ETH": "Ethereum Ether 以太坊"
        case "SOL": "Solana 索拉纳"
        case "NVDA": "NVIDIA 英伟达"
        case "TSLA": "Tesla 特斯拉"
        case "AAPL": "Apple 苹果"
        default: ""
        }
    }
}

struct AppSearchIndex {
    struct Document {
        let item: AppSearchItem
        let exact: [String]
        let text: String
        init(_ item: AppSearchItem, exact: [String], fields: [String]) {
            self.item = item
            self.exact = exact.map(AppSearchQuery.fold)
            text = AppSearchQuery.fold((exact + fields).joined(separator: " "))
        }
        func rank(_ query: AppSearchQuery) -> Int? {
            guard !query.terms.isEmpty else { return 0 }
            let whole = AppSearchQuery.fold(query.text)
            if case .ticker(let value) = item, AppSearchQuery.fold(value.symbol) == whole { return -1 }
            if exact.contains(whole) { return 0 }
            guard query.terms.allSatisfy({ term in
                text.contains(term) || item.ticker.map { AppSearchQuery.fold(AppSearchQuery.aliases($0)).contains(term) } == true
            }) else { return nil }
            if exact.contains(where: { $0.hasPrefix(whole) }) { return 1 }
            return 2
        }
    }
    let documents: [Document]
    init(items: [AppSearchItem] = []) {
        var seen = Set<String>()
        documents = items.filter { seen.insert($0.id).inserted }.map { item in
            switch item {
            case .ticker(let value):
                return Document(item, exact: [value.symbol, value.companyName], fields: [AppSearchQuery.aliases(value.symbol)])
            case .opinion(let value):
                return Document(item, exact: [value.ticker], fields: [value.companyName, value.authorName, value.platform,
                    value.thesis, value.originalText ?? "", value.activityTitle ?? "", value.activityTitleZH ?? "",
                    value.activityTitleEN ?? "", value.translatedText ?? "", value.translatedTextZH ?? "", value.translatedTextEN ?? ""])
            case .movement(let value):
                return Document(item, exact: [value.ticker], fields: [value.companyName, value.publicIdentity.displayName,
                    value.accountLabel, value.market, value.action.rawValue, value.direction.rawValue])
            case .author(let value):
                return Document(item, exact: [value.name, value.handle.trimmingCharacters(in: CharacterSet(charactersIn: "@"))],
                    fields: [value.platform, value.specialty, value.horizon, value.style ?? "", value.description ?? "",
                             value.resolvedTopTickers.joined(separator: " ")])
            case .money(let value):
                return Document(item, exact: [value.publicIdentity.displayName, value.walletLabel, value.address ?? ""],
                    fields: [value.ticker, value.style ?? "", value.source ?? "", "Hyperliquid Smart Money",
                             value.currentPositions?.map(\.symbol).joined(separator: " ") ?? ""])
            case .user(let value):
                return Document(item, exact: [value.nickname, value.handle ?? ""], fields: [])
            }
        }
    }

    func search(_ raw: String) -> [AppSearchItem] {
        let query = AppSearchQuery(raw)
        return documents.compactMap { doc -> (AppSearchItem, Int)? in
            doc.rank(query).map { (doc.item, $0) }
        }.sorted {
            let left = AppSearchCategory.allCases.firstIndex(of: $0.0.category)!
            let right = AppSearchCategory.allCases.firstIndex(of: $1.0.category)!
            if left != right { return left < right }
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            if $0.0.date != $1.0.date { return $0.0.date > $1.0.date }
            return $0.0.id < $1.0.id
        }.map(\.0)
    }
}

extension AppModel {
    func searchItems(markets: [HyperliquidPerpMarket]) -> [AppSearchItem] {
        tickerCatalog(markets: markets).map(AppSearchItem.ticker)
            + (smartAccountUpdates + smartAccountEvidenceByAuthor.values.flatMap { $0 }).map(AppSearchItem.opinion)
            + smartMoneyMovements.map(AppSearchItem.movement)
            + smartAccounts.map(AppSearchItem.author) + smartMoney.map(AppSearchItem.money)
    }
}
