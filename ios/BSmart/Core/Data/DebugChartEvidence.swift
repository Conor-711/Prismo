#if DEBUG
import Foundation

/// Explicit UI-test sample only; never a substitute for missing production candles.
enum DebugChartEvidence {
    static func money(accountID: String) -> [SmartMoneyRepresentativeEvidence] {
        let start = Date(timeIntervalSince1970: 1_783_468_800)
        let candles = (0..<60).map { index in
            let open = 100 + Double(index) * 0.5
            return SmartMoneyCandle(timestamp: start.addingTimeInterval(Double(index) * 14_400),
                                   open: open, high: open + 3, low: open - 2,
                                   close: open + (index.isMultiple(of: 2) ? 1 : -1), volume: 10)
        }
        let markers = [12, 25, 42].map { index in
            SmartMoneyEntryMarker(id: UUID(), observedAt: candles[index].timestamp,
                                  price: candles[index].open, priceBasis: "UI test fixture",
                                  direction: .bullish, action: .increased, entryNotional: 1000, evidenceURL: nil)
        }
        return [SmartMoneyRepresentativeEvidence(
            id: UUID(), accountId: accountID, accountDisplayName: "UI test", avatarVariant: nil,
            ticker: "NVDA", market: "xyz:NVDA", representativeRank: 1, cumulativeEntryNotional: 3000,
            entryCount: markers.count, assetNetPnl: 0, latestEntryAt: markers.last!.observedAt,
            priceEvidence: SmartMoneyPriceEvidence(market: "xyz:NVDA", interval: "4h", source: "UI test fixture",
                                                  candles: candles, entryMarkers: markers))]
    }
}
#endif
