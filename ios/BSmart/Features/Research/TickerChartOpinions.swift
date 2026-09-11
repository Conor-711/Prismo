import CoreGraphics
import Foundation

struct TickerChartOpinionPolicy {
    let maximumCount: Int
    let avatarSize: CGFloat
    var footprint: CGSize { CGSize(width: max(52, avatarSize + 12), height: avatarSize + 22) }

    init(range: HyperliquidChartRange) {
        switch range {
        case .oneHour: maximumCount = 3; avatarSize = 38
        case .fourHours: maximumCount = 4; avatarSize = 36
        case .oneDay: maximumCount = 5; avatarSize = 34
        case .oneWeek: maximumCount = 6; avatarSize = 30
        case .oneMonth: maximumCount = 7; avatarSize = 28
        }
    }
}

struct TickerChartOpinion: Identifiable {
    let activity: TickerSmartActivityItem
    let date: Date
    let price: Double
    var id: String { activity.id }

    var rankLabel: String {
        switch activity.payload {
        case let .account(update):
            let percentile = update.platformPercentile
            guard percentile.isFinite, (0...1).contains(percentile) else { return "—" }
            return "Top \(max(1, Int(ceil(percentile * 100))))%"
        case let .money(movement):
            return movement.accountScore.isFinite
                ? "Score \(movement.accountScore.formatted(.number.precision(.fractionLength(0))))" : "—"
        }
    }

    private var subject: String {
        switch activity.payload {
        case let .account(update): "account:\(update.authorId)"
        case let .money(movement): "money:\(movement.accountId.lowercased())"
        }
    }

    static func visibleActivities(_ activities: [TickerSmartActivityItem], symbol: String,
                                  candles: [HyperliquidCandle], range: HyperliquidChartRange,
                                  now: Date = Date()) -> [TickerSmartActivityItem] {
        guard let first = candles.first, let last = candles.last else { return [] }
        let start = max(first.openTime, now.addingTimeInterval(-range.duration))
        let end = min(last.closeTime, now)
        return activities.filter {
            let ticker: String = switch $0.payload {
            case let .account(update): update.ticker
            case let .money(movement): movement.ticker
            }
            return ticker.caseInsensitiveCompare(symbol) == .orderedSame
                && $0.occurredAt >= start && $0.occurredAt <= end
        }
    }

    static func candidates(activities: [TickerSmartActivityItem], candles: [HyperliquidCandle]) -> [Self] {
        var subjects = Set<String>()
        // Keep the latest judgment per subject. Never move an out-of-range post onto the last candle.
        let latest = activities.sorted {
            $0.occurredAt != $1.occurredAt ? $0.occurredAt > $1.occurredAt : $0.id < $1.id
        }.compactMap { activity -> Self? in
            guard let candle = candles.last(where: {
                activity.occurredAt >= $0.openTime && activity.occurredAt <= $0.closeTime
            }), candle.close.isFinite, candle.close > 0 else { return nil }
            // Anchor to this chart's market price, never a differently scaled equity evidence quote.
            let item = Self(activity: activity, date: activity.occurredAt, price: candle.close)
            return subjects.insert(item.subject).inserted ? item : nil
        }
        let accounts = latest.filter { $0.activity.source == .smartAccount }.sorted {
            func percentile(_ item: Self) -> Double {
                guard case let .account(update) = item.activity.payload,
                      update.platformPercentile.isFinite, (0...1).contains(update.platformPercentile) else { return 1.01 }
                return update.platformPercentile
            }
            if percentile($0) != percentile($1) { return percentile($0) < percentile($1) }
            return $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id
        }
        let money = latest.filter { $0.activity.source == .smartMoney }.sorted {
            if $0.activity.score != $1.activity.score { return $0.activity.score > $1.activity.score }
            return $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id
        }
        // Scores from different leaderboards are not directly comparable.
        return (0..<max(accounts.count, money.count)).flatMap { index in
            [accounts.indices.contains(index) ? accounts[index] : nil,
             money.indices.contains(index) ? money[index] : nil].compactMap { $0 }
        }
    }
}

struct TickerChartOpinionPlacement: Identifiable {
    let opinion: TickerChartOpinion
    let anchor: CGPoint
    let frame: CGRect
    var id: String { opinion.id }

    static func layout(_ anchors: [(TickerChartOpinion, CGPoint)], in bounds: CGRect,
                       policy: TickerChartOpinionPolicy) -> [Self] {
        let size = policy.footprint
        guard bounds.width >= size.width, bounds.height >= size.height else { return [] }
        var result: [Self] = []
        for (opinion, anchor) in anchors {
            guard result.count < policy.maximumCount else { break }
            let x = min(max(anchor.x, bounds.minX + size.width / 2), bounds.maxX - size.width / 2)
            for offset in [CGFloat(0), -size.height - 8, size.height + 8] {
                let y = min(max(anchor.y + offset, bounds.minY + size.height / 2), bounds.maxY - size.height / 2)
                let frame = CGRect(x: x - size.width / 2, y: y - size.height / 2,
                                   width: size.width, height: size.height)
                guard !result.contains(where: { $0.frame.insetBy(dx: -4, dy: -4).intersects(frame) }) else { continue }
                result.append(Self(opinion: opinion, anchor: anchor, frame: frame))
                break
            }
        }
        return result
    }
}
