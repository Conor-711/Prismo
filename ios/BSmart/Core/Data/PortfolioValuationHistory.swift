import Foundation

struct PortfolioValuationHistory: Codable {
    var context: String
    var points: [PortfolioValuePoint]

    static func context(for positions: [PortfolioPosition]) -> String {
        positions.filter(\.isPosition).map {
            "\($0.ticker.uppercased()):\($0.shares):\($0.portfolioWeight ?? 0)"
        }.sorted().joined(separator: "|")
    }

    static func normalized(_ points: [PortfolioValuePoint], now: Date) -> [PortfolioValuePoint] {
        var values: [Date: PortfolioValuePoint] = [:]
        for point in points where point.value.isFinite && point.value >= 0
            && point.timestamp <= now && point.timestamp.timeIntervalSince(now) >= -366 * 86_400 {
            values[point.timestamp] = point
        }
        return Array(values.values.sorted { $0.timestamp < $1.timestamp }.suffix(10_000))
    }

    static func recording(_ value: Double, at date: Date, in points: [PortfolioValuePoint]) -> [PortfolioValuePoint] {
        var result = normalized(points, now: date)
        guard value.isFinite, value >= 0 else { return result }
        // Coalesce quote bursts without rewriting older valuation observations.
        if let last = result.last, date.timeIntervalSince(last.timestamp) < 60 {
            if last.value == value { return result }
            if result.count > 1 || last.timestamp == date { result.removeLast() }
        }
        result.append(PortfolioValuePoint(timestamp: date, value: value))
        return Array(result.suffix(10_000))
    }
}
