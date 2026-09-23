import Foundation

struct ExternalTradeDestination: Identifiable, Equatable {
    let name: String
    let logoAssetName: String
    let url: URL
    var id: String { name }
}

enum ExternalTradeLinks {
    private static let cryptoSlugs = [
        "BTC": "bitcoin", "ETH": "ethereum", "SOL": "solana",
        "XRP": "xrp", "DOGE": "dogecoin",
    ]

    static func destinations(for symbol: String) -> [ExternalTradeDestination] {
        let ticker = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard ticker.range(of: #"^[A-Z][A-Z0-9]{0,9}$"#, options: .regularExpression) != nil else { return [] }
        if let slug = cryptoSlugs[ticker] {
            return [
                .init(name: "Coinbase", logoAssetName: "TradeVenue_Coinbase", url: URL(string: "https://www.coinbase.com/price/\(slug)")!),
                .init(name: "Kraken", logoAssetName: "TradeVenue_Kraken", url: URL(string: "https://www.kraken.com/prices/\(slug)")!),
            ]
        }
        return [
            .init(name: "Robinhood", logoAssetName: "TradeVenue_Robinhood", url: URL(string: "https://robinhood.com/us/en/stocks/\(ticker)/")!),
            .init(name: "eToro", logoAssetName: "TradeVenue_eToro", url: URL(string: "https://www.etoro.com/markets/\(ticker.lowercased())")!),
            .init(name: "moomoo", logoAssetName: "TradeVenue_moomoo", url: URL(string: "https://www.moomoo.com/stock/\(ticker)-US")!),
        ]
    }
}
