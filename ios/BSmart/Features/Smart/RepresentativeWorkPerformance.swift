import Foundation

/// A price-window result is never an annualized return or the author's realized P&L.
struct RepresentativeWorkPerformance {
    let percent: Double
    let startDay: String
    let endDay: String
    let startPrice: Double
    let endPrice: Double

    init?(update: SmartAccountUpdate) {
        if let result = update.settlement,
           let percent = result.tickerReturnPercent,
           let start = result.entryDay, let end = result.exitDay,
           let entry = result.entryPrice, let exit = result.exitPrice,
           Self.valid(percent, start, end, entry, exit) {
            self.percent = percent
            startDay = start; endDay = end; startPrice = entry; endPrice = exit
        } else if let result = update.priceEvidence,
                  let percent = result.responsePercent,
                  Self.valid(percent, result.viewDay, result.latestDay, result.viewPrice, result.latestPrice) {
            self.percent = percent
            startDay = result.viewDay; endDay = result.latestDay
            startPrice = result.viewPrice; endPrice = result.latestPrice
        } else { return nil }
    }

    private static func valid(_ percent: Double, _ start: String, _ end: String,
                              _ entry: Double, _ exit: Double) -> Bool {
        percent.isFinite && entry.isFinite && exit.isFinite && entry > 0 && exit > 0
            && BSmartChartCandle.day(start) != nil && BSmartChartCandle.day(end) != nil && start <= end
    }
}
