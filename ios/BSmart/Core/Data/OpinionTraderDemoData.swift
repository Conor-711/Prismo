import Foundation

/// Display-only identities and positions. Never encoded into the real trade API.
struct OpinionTraderDemoData {
    struct Trader: Identifiable {
        let id: Int
        let nickname: String
        let avatarAsset: String
        let side: OpinionTrader.Side
        let entryPrice: Double
        let notionalUSD: Double
        let leverage: Int
        let openedAt: Date
    }

    let ticker: String
    let traders: [Trader]
    let privateTraderCount = 2
    var totalTraders: Int { traders.count + privateTraderCount }

    init(ticker: String, referencePrice: Double?, now: Date) {
        self.ticker = ticker.uppercased()
        let price = referencePrice.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 100
        let names = ["Casey", "Mia", "Ethan", "Zoe", "Lucas", "Nina"]
        let assets = ["SmartMoneyBorderCollieGlasses", "SmartMoneyBorderCollieBandana",
                      "SmartMoneyBorderCollieCap", "SmartMoneyBorderCollieBowTie",
                      "SmartMoneyBorderCollieBrown", "SmartMoneyBorderCollie"]
        let notionals: [Double] = [1500, 800, 3200, 650, 2400, 1200]
        let leverage = [3, 2, 5, 2, 3, 4]
        let ages: [TimeInterval] = [180, 1020, 2520, 5400, 14400, 28800]
        traders = names.indices.map { index in
            Trader(id: index, nickname: names[index], avatarAsset: assets[index],
                   side: index == 2 || index == 4 ? .short : .long,
                   entryPrice: price * (1 + Double(index - 2) * 0.0025),
                   notionalUSD: notionals[index], leverage: leverage[index],
                   openedAt: now.addingTimeInterval(-ages[index]))
        }
    }
}
