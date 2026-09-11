import XCTest
@testable import BSmart

final class PriceChartInteractionTests: XCTestCase {
    private func date(_ value: Double) -> Date { Date(timeIntervalSince1970: value) }
    private var bounds: ClosedRange<Date> { date(0)...date(100) }

    func testZoomPreservesAnchorAndRespectsMinimumSpan() {
        let zoom = BSmartChartViewport.zoom(bounds, scale: 2, anchor: 0.25, bounds: bounds, minimumSpan: 8)
        XCTAssertEqual(zoom.lowerBound.timeIntervalSince1970, 12.5)
        XCTAssertEqual(zoom.upperBound.timeIntervalSince1970, 62.5)
        let limit = BSmartChartViewport.zoom(zoom, scale: 100, anchor: 0.5, bounds: bounds, minimumSpan: 8)
        XCTAssertEqual(limit.upperBound.timeIntervalSince(limit.lowerBound), 8)
    }

    func testZoomOutCannotEscapeDataAndInvalidScalesAreIgnored() {
        let window = date(30)...date(50)
        XCTAssertEqual(BSmartChartViewport.zoom(window, scale: 0.001, anchor: 1, bounds: bounds, minimumSpan: 8), bounds)
        for scale in [Double.nan, .infinity, 0, -1] {
            XCTAssertEqual(BSmartChartViewport.zoom(window, scale: scale, anchor: 0.5, bounds: bounds, minimumSpan: 8), window)
        }
    }

    func testPanKeepsWindowWidthAndClampsBothEdges() {
        let window = date(30)...date(50)
        XCTAssertEqual(BSmartChartViewport.pan(window, fraction: 0.5, bounds: bounds), date(20)...date(40))
        XCTAssertEqual(BSmartChartViewport.pan(window, fraction: 100, bounds: bounds), date(0)...date(20))
        XCTAssertEqual(BSmartChartViewport.pan(window, fraction: -100, bounds: bounds), date(80)...date(100))
        XCTAssertEqual(BSmartChartViewport.pan(bounds, fraction: -1, bounds: bounds), bounds)
    }

    func testShortHistoryNeverZoomsPastAvailableData() {
        let small = date(0)...date(2)
        XCTAssertEqual(BSmartChartViewport.zoom(small, scale: 100, anchor: 0.5, bounds: small, minimumSpan: 8), small)
        XCTAssertEqual(BSmartChartViewport.clamped(bounds, to: small, minimumSpan: 8), small)
    }

    func testValidationDeduplicatesWithoutSynthesizingOHLC() {
        let doji = candle(time: 1, close: 10)
        let invalid = BSmartChartCandle(time: date(2), interval: 1, open: 10, high: 9, low: 8, close: 10)
        let nan = BSmartChartCandle(time: date(3), interval: 1, open: 10, high: 12, low: 8, close: .nan)
        let series = BSmartPriceChartSeries([candle(time: 4), doji, invalid, nan, doji])
        XCTAssertEqual(series.candles.map(\.time), [date(1), date(4)])
        XCTAssertEqual(series.candles.first?.open, series.candles.first?.close)
        XCTAssertEqual(series.nearest(to: date(3.5))?.time, date(4))
    }

    func testPriceAxisUsesVisibleCandlesAndVisibleEvidenceOnly() {
        let high = BSmartChartCandle(time: date(100), interval: 1, open: 100, high: 120, low: 80, close: 100)
        let series = BSmartPriceChartSeries([candle(time: 1), candle(time: 2), high])
        XCTAssertLessThan(series.priceDomain(in: date(0)...date(4), including: []).upperBound, 20)
        XCTAssertGreaterThan(series.priceDomain(in: date(0)...date(4), including: [30]).upperBound, 30)
        XCTAssertEqual(series.visible(in: date(0)...date(4)).count, 2)
        XCTAssertTrue(series.priceDomain(in: date(30)...date(40), including: [.nan]).upperBound.isFinite)
    }

    func testDailyAdapterRetainsDatesAndRejectsMalformedDays() {
        XCTAssertNil(BSmartChartCandle.day("2026-02-30"))
        XCTAssertNil(BSmartChartCandle.day("invalid"))
        let day = PriceCandle(day: "2026-09-01", open: 10, high: 12, low: 8, close: 11, volume: 1)
        let series = BSmartPriceChartSeries(BSmartChartCandle.daily([day]))
        XCTAssertEqual(series.candles.first?.interval, 86_400)
        XCTAssertEqual(series.candles.first?.time, BSmartChartCandle.day(day.day))
        XCTAssertEqual(series.candles.first?.close, day.close)
    }

    func testEmptyHistoryHasFiniteNonZeroDomain() {
        let series = BSmartPriceChartSeries([])
        XCTAssertTrue(series.candles.isEmpty)
        XCTAssertGreaterThan(series.bounds.upperBound, series.bounds.lowerBound)
        XCTAssertGreaterThan(series.priceDomain(in: series.bounds, including: []).upperBound, 0)
        XCTAssertNil(series.nearest(to: date(0)))
    }

    private func candle(time: Double, close: Double = 11) -> BSmartChartCandle {
        BSmartChartCandle(time: date(time), interval: 1, open: 10, high: 12, low: 8, close: close)
    }
}
