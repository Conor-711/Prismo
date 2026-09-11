import Charts
import SwiftUI

/// A temporal candle needs an explicit body span; a ratio has no bin width on a continuous axis.
struct BSmartCandlestick: ChartContent {
    let time: Date
    let interval: TimeInterval
    let open: Double
    let high: Double
    let low: Double
    let close: Double

    private var color: Color { close >= open ? BSmartColor.bull : BSmartColor.bear }
    private var halfWidth: TimeInterval { interval * 0.32 }

    var body: some ChartContent {
        RuleMark(x: .value("Time", time), yStart: .value("Low", low), yEnd: .value("High", high))
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: 0.7, lineCap: .butt))
        if open == close {
            RuleMark(xStart: .value("Body start", time.addingTimeInterval(-halfWidth)),
                     xEnd: .value("Body end", time.addingTimeInterval(halfWidth)),
                     y: .value("Open / Close", close))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1))
        } else {
            RectangleMark(xStart: .value("Body start", time.addingTimeInterval(-halfWidth)),
                          xEnd: .value("Body end", time.addingTimeInterval(halfWidth)),
                          yStart: .value("Body low", min(open, close)),
                          yEnd: .value("Body high", max(open, close)))
                .foregroundStyle(color)
        }
    }
}
