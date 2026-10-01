import Foundation

struct TodayFeedDisplayOptions: Equatable {
    var activityType: TodayFeedActivityType = .all
    var followingOnly = false
    var trendingOnly = false
    var timeSort: TodayFeedTimeSort = .newest
    var isPreview = false
}

struct TodayFeedSourceProjection {
    let runs: [TodayHomeFeedRun]

    static func prepare(from items: [TodayHomeFeedItem], options: TodayFeedDisplayOptions,
                        trackedInvestors: Set<String> = [], trackedSubjects: Set<String> = [],
                        now: Date = Date()) -> [AccountPlatformFilter: Self] {
        let eligible = items.filter { item in
            switch item {
            case let .investor(investor):
                return options.activityType.matches(investor.latest)
                    && (!options.followingOnly || trackedInvestors.contains(investor.id))
            case let .subject(subject, _):
                return !options.isPreview && options.activityType.matches(subject.latest)
                    && (!options.followingOnly || trackedSubjects.contains(subject.id))
            }
        }
        // A disclosed day is shared by many events; parse it once, outside sort comparisons.
        var days: [String: Date] = [:]
        var dates: [String: Date] = [:]
        for item in eligible {
            if Task.isCancelled { return [:] }
            if case let .subject(subject, _) = item {
                let day = subject.latest.displayDay
                let date = days[day] ?? SubjectFeedDay.parse(day)
                days[day] = date
                dates[item.id] = date
            } else {
                dates[item.id] = item.occurredAt
            }
        }
        let dateForItem: (TodayHomeFeedItem) -> Date = { dates[$0.id] ?? $0.occurredAt }
        var result: [AccountPlatformFilter: Self] = [:]
        for source in AccountPlatformFilter.allCases {
            if Task.isCancelled { return [:] }
            let matching = eligible.filter { item in
                switch item {
                case let .investor(investor): return options.isPreview || source.matches(investor)
                case let .subject(subject, _): return source.matches(subject)
                }
            }
            let merged = TodayHomeFeedItem.mergeAdjacent(matching, dateForItem: dateForItem)
            let sorted = TodayHomeFeedOrder.sorted(merged, trending: options.trendingOnly,
                timeSort: options.timeSort, now: now, dateForItem: dateForItem)
            result[source] = Self(runs: TodayHomeFeedRun.consecutive(sorted))
        }
        return result
    }
}
