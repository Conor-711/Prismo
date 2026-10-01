import Foundation

/// Editorial priority for the home rail only; never changes investor rankings.
enum TodayHomeTrendOrder {
    static let featuredSubjectIDs = [
        "politician:P000197", "celebrity:peter-thiel", "celebrity:duan-yongping",
        "institution:citadel", "celebrity:bill-ackman", "celebrity:leopold-aschenbrenner",
        "celebrity:warren-buffett",
    ]

    static func activities(updates: [SmartAccountUpdate], movements: [SmartMoneyMovement],
                           snapshot: TodaySubjectFeedSnapshot, now: Date = Date(),
                           limit: Int = 8) -> [TodayHomeFeedItem] {
        guard limit > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-7 * 86_400)
        let investors = TodayInvestorActivity.groups(
            accountUpdates: updates, moneyMovements: movements, now: now
        ).flatMap { investor in
            investor.activities.filter { $0.occurredAt >= cutoff }.map {
                TodayHomeFeedItem.investor(.init(id: investor.id, activities: [$0]))
            }
        }
        let groups = TodaySubjectActivity.groups(from: snapshot, now: now)
        let recentSubjects = groups.flatMap { subject in
            subject.events.filter { $0.displayedAt >= cutoff && !$0.isSample }.map {
                TodayHomeFeedItem.subject(.init(subject: subject.subject, events: [$0]), subject)
            }
        }

        // Quarterly reports can be older than seven days. Keep the real filing date,
        // and use the same bounded 400-day history as the server's home projection.
        let oldestDay = SubjectFeedDay.format(now.addingTimeInterval(-400 * 86_400))
        let today = SubjectFeedDay.format(now)
        let featuredIDs = Set(featuredSubjectIDs)
        let profiles = Dictionary(uniqueKeysWithValues: snapshot.subjects.map { ($0.id, $0) })
        let events = Dictionary(grouping: snapshot.events.filter {
            featuredIDs.contains($0.subjectID) && !$0.isSample
                && $0.displayDay >= oldestDay && $0.displayDay <= today
        }, by: \.subjectID)
        var selected = featuredSubjectIDs.compactMap { id -> TodayHomeFeedItem? in
            guard let profile = profiles[id], let history = events[id], !history.isEmpty else { return nil }
            let sorted = history.sorted { $0.displayDay == $1.displayDay
                ? $0.id > $1.id : $0.displayDay > $1.displayDay }
            let parent = TodaySubjectActivity(subject: profile, events: sorted)
            return .subject(.init(subject: profile, events: [parent.latest]), parent)
        }
        var seen = Set(selected.map(\.actorID))
        selected += TodayHomeFeedOrder.sorted(investors + recentSubjects, trending: true,
                                              timeSort: .newest, now: now)
            .filter { seen.insert($0.actorID).inserted }
        return Array(selected.prefix(limit))
    }
}
