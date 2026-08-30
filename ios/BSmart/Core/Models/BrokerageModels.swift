import Foundation

enum BrokerageProvider: String, Codable, CaseIterable, Identifiable {
    case robinhood
    case interactiveBrokers = "interactive_brokers"
    case binance
    case coinbase

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .robinhood: "Robinhood"
        case .interactiveBrokers: "Interactive Brokers"
        case .binance: "Binance"
        case .coinbase: "Coinbase"
        }
    }

}

struct LinkedBrokerageAccount: Identifiable, Codable, Hashable {
    let id: UUID
    let provider: BrokerageProvider
    let connectedAt: Date
    var lastSyncedAt: Date
    var detectedHoldingCount: Int
    var importedPositionCount: Int
    var isPrototype: Bool
}

struct BrokerageHoldingPreview: Identifiable, Hashable {
    let ticker: String
    let name: String
    let quantity: Double
    let averageCost: Double
    let estimatedValue: Double
    let isSupported: Bool

    var id: String { ticker }
}
