import XCTest
@testable import BSmart

final class RepresentativeWorkChartTests: XCTestCase {
    func testSelectsTopThreeValidViewsWithoutClampingOldViews() {
        let markers = [marker("2026-08-01", score: 999), marker("2026-09-01", score: 1),
                       marker("2026-09-02", score: 3), marker("2026-09-03", score: 2),
                       marker("2026-09-04", score: 4), marker("2026-09-09", score: 100)]
        let chart = RepresentativeWorkChartModel(update: update, evidence: evidence(markers: markers))
        XCTAssertEqual(chart.markers.map { $0.opinion.contribution }.sorted(), [2, 3, 4])
        XCTAssertTrue(chart.markers.allSatisfy { (0...4).contains($0.session) })
        XCTAssertEqual(chart.axisSessions, [0, 2, 4])
    }

    func testInvalidCandlesAreExcludedAndFallbackRetainsActualViewPrice() {
        var evidence = evidence(markers: [])
        evidence = SmartAccountPriceEvidence(ticker: "NVDA", viewDay: "2026-09-03", viewPrice: 121,
            latestDay: "2026-09-05", latestPrice: 130, responsePercent: nil, source: "NASDAQ",
            candles: evidence.candles.reversed() + [PriceCandle(day: "invalid", open: 1, high: 1, low: 1, close: 1, volume: 1)])
        let chart = RepresentativeWorkChartModel(update: update, evidence: evidence)
        XCTAssertEqual(chart.candles.count, 5)
        XCTAssertEqual(chart.candles.first?.day, "2026-09-01")
        XCTAssertEqual(chart.markers.first?.session, 2)
        XCTAssertEqual(chart.markers.first?.opinion.viewPrice, 121)
        XCTAssertEqual(chart.markers.first?.id, update.id)
    }

    func testThreeCoincidentBubblesHaveSeparateTouchTargets() {
        for width in [240.0, 320, 600] {
            for anchor in [CGPoint.zero, CGPoint(x: width, y: 240), CGPoint(x: width / 2, y: 120)] {
                let points = RepresentativeMarkerLayout.positions(anchors: Array(repeating: anchor, count: 3),
                                                                 size: CGSize(width: width, height: 240))
                XCTAssertEqual(points.count, 3)
                for (index, point) in points.enumerated() {
                    XCTAssertTrue((22...(width - 22)).contains(point.x))
                    XCTAssertTrue((22...218).contains(point.y))
                    for other in points.dropFirst(index + 1) {
                        XCTAssertGreaterThanOrEqual(hypot(point.x - other.x, point.y - other.y), 46)
                    }
                }
            }
        }
    }

    private func marker(_ day: String, score: Double) -> SmartAccountOpinionMarker {
        SmartAccountOpinionMarker(id: UUID(), publishedAt: Date(), viewDay: day, viewPrice: 120,
            direction: .bullish, contribution: score, horizon: "60D", thesis: "Growing demand", evidenceURL: nil)
    }
    private func evidence(markers: [SmartAccountOpinionMarker]) -> SmartAccountPriceEvidence {
        SmartAccountPriceEvidence(ticker: "NVDA", viewDay: "2026-09-03", viewPrice: 120,
            latestDay: "2026-09-05", latestPrice: 130, responsePercent: nil, source: "NASDAQ",
            candles: (1...5).map { PriceCandle(day: "2026-09-0\($0)", open: 120, high: 135, low: 110, close: 130, volume: 10) },
            opinionMarkers: markers)
    }
    private let update = SmartAccountUpdate(id: UUID(), ticker: "NVDA", companyName: "NVIDIA",
        authorId: "author", authorName: "Author", platform: "X", score: 90, platformPercentile: 0.01,
        direction: .bullish, lifecycle: .new, horizon: "60D", targetPrice: nil, thesis: "Growing demand",
        invalidation: nil, publishedAt: Date(), evidenceURL: nil)
}
