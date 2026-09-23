import Foundation

enum TodayInAppPositionSide: Equatable {
    case long, short, both

    var label: String {
        switch self {
        case .long: "Long".bSmartLocalized
        case .short: "Short".bSmartLocalized
        case .both: "Long".bSmartLocalized + " / " + "Short".bSmartLocalized
        }
    }
}

/// A presentation-only projection of declared and in-app holdings against existing Smart evidence.
struct TodayHoldingsActivity: Equatable {
    var tickers: [String] = []
    var weights: [String: Double] = [:]
    var inAppSides: [String: TodayInAppPositionSide] = [:]
    var activities: [TodayActivity] = []

    var preview: [TodayActivity] {
        preview(source: .all)
    }

    func preview(source: TodayActivityFilter) -> [TodayActivity] {
        let matching = filtered(source: source, ticker: nil)
        var seen = Set<String>()
        let diversified = matching.filter { seen.insert(Self.symbol($0.ticker)).inserted }
        let chosen = Array(diversified.prefix(3))
        let remaining = matching.filter { !chosen.contains($0) }
        let ids = Set((chosen + remaining.prefix(max(0, 3 - chosen.count))).map(\.id))
        return matching.filter { ids.contains($0.id) }
    }

    func filtered(source: TodayActivityFilter, ticker: String?) -> [TodayActivity] {
        activities.filter { activity in
            let matchesTicker = ticker == nil || Self.symbol(activity.ticker) == Self.symbol(ticker ?? "")
            let matchesSource = source == .all || (source == .accounts) == activity.isSmartAccount
            return matchesTicker && matchesSource
        }
    }

    static func make(
        positions: [PortfolioPosition],
        accountUpdates: [SmartAccountUpdate],
        moneyMovements: [SmartMoneyMovement],
        tradingPositions: [TradingPositionRow] = [],
        now: Date = .now
    ) -> Self {
        let holdings = positions.filter { $0.isPosition && !symbol($0.ticker).isEmpty }
        var inAppSides: [String: TodayInAppPositionSide] = [:]
        for position in tradingPositions where position.quantity.magnitude.isPositive {
            let ticker = symbol(position.symbol)
            guard !ticker.isEmpty else { continue }
            let side: TodayInAppPositionSide = position.quantity.isNegative ? .short : .long
            if let previous = inAppSides[ticker], previous != side {
                inAppSides[ticker] = .both
            } else {
                inAppSides[ticker] = side
            }
        }
        let tickers = Set(holdings.map { symbol($0.ticker) }).union(inAppSides.keys)
        // The two sources have no shared valuation basis, so a manual-only weight would mislead.
        let weights = inAppSides.isEmpty ? holdingWeights(holdings) : [:]
        let earliest = now.addingTimeInterval(-30 * 86_400)
        var latest: [String: TodayActivity] = [:]

        func retain(_ activity: TodayActivity, key: String) {
            guard tickers.contains(symbol(activity.ticker)),
                  activity.occurredAt >= earliest, activity.occurredAt <= now else { return }
            if let previous = latest[key],
               previous.occurredAt > activity.occurredAt
                || (previous.occurredAt == activity.occurredAt && previous.id.uuidString < activity.id.uuidString) {
                return
            }
            latest[key] = activity
        }

        for update in accountUpdates {
            let platform = update.platform.lowercased() == "twitter" ? "x" : update.platform.lowercased()
            retain(.account(TodayAccountActivity(updates: [update])),
                   key: "account|\(platform)|\(update.authorId.lowercased())|\(symbol(update.ticker))")
        }
        for movement in moneyMovements {
            retain(.money(TodayMoneyActivity(movements: [movement])),
                   key: "money|\(movement.accountId.lowercased())|\(movement.market.lowercased())|\(symbol(movement.ticker))")
        }

        // Recency bands prevent large holdings from lifting stale events above today's news.
        func ageBand(_ date: Date) -> Int {
            let age = now.timeIntervalSince(date)
            if age < 86_400 { return 0 }
            if age < 3 * 86_400 { return 1 }
            if age < 7 * 86_400 { return 2 }
            return 3
        }
        let sorted = latest.values.sorted { lhs, rhs in
            let leftBand = ageBand(lhs.occurredAt), rightBand = ageBand(rhs.occurredAt)
            if leftBand != rightBand { return leftBand < rightBand }
            let leftWeight = weights[symbol(lhs.ticker)] ?? 0
            let rightWeight = weights[symbol(rhs.ticker)] ?? 0
            if leftWeight != rightWeight { return leftWeight > rightWeight }
            if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt > rhs.occurredAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return Self(tickers: tickers.sorted(), weights: weights, inAppSides: inAppSides, activities: sorted)
    }

    static func symbol(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func holdingWeights(_ positions: [PortfolioPosition]) -> [String: Double] {
        let groups = Dictionary(grouping: positions) { symbol($0.ticker) }
        let completeValuation = !positions.isEmpty && positions.allSatisfy {
            $0.shares.isFinite && $0.shares != 0 && $0.currentPrice.isFinite && $0.currentPrice > 0
                && $0.marketValue.isFinite
        }
        let totalValue = positions.reduce(0) { $0 + abs($1.marketValue) }
        let declared = positions.compactMap(\.portfolioWeight)
        let validDeclarations = declared.allSatisfy { $0.isFinite && $0 > 0 && $0 <= 1 }
            && declared.reduce(0, +) <= 1.000_001
        var weights: [String: Double] = [:]
        for (ticker, lots) in groups {
            if validDeclarations && lots.allSatisfy({ $0.portfolioWeight != nil }) {
                weights[ticker] = lots.compactMap(\.portfolioWeight).reduce(0, +)
            } else if completeValuation && totalValue.isFinite && totalValue > 0 {
                // Include every holding in the denominator, not just tickers with Smart coverage.
                weights[ticker] = lots.reduce(0) { $0 + abs($1.marketValue) } / totalValue
            }
        }
        return weights
    }
}
