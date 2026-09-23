import Foundation

struct ActivityNotification: Identifiable, Hashable {
    enum Payload: Hashable {
        case account(SmartAccountUpdate)
        case money(SmartMoneyMovement)
        case follower(SocialPerson)
    }
    let payload: Payload
    let tracked: Bool
    let held: Bool

    var id: String {
        switch payload {
        case .account(let update): "account:\(update.id)"
        case .money(let movement): "money:\(movement.id)"
        case .follower(let person): "follower:\(person.id)"
        }
    }
    var occurredAt: Date {
        switch payload {
        case .account(let update): update.publishedAt
        case .money(let movement): movement.observedAt
        case .follower(let person): person.at
        }
    }
    var ticker: String {
        switch payload {
        case .account(let update): update.ticker
        case .money(let movement): movement.ticker
        case .follower: ""
        }
    }

    var isFollow: Bool {
        if case .follower = payload { return true }
        return false
    }

    static func build(updates: [SmartAccountUpdate], movements: [SmartMoneyMovement],
                      followedAccounts: Set<String>, followedMoney: Set<String>,
                      heldTickers: Set<String>, profiles: [SmartAccountProfile] = [],
                      followers: [SocialPerson] = [],
                      now: Date = .now) -> [Self] {
        let accounts = Set(followedAccounts.map { $0.lowercased() })
        let money = Set(followedMoney.map { $0.lowercased() })
        let held = Set(heldTickers.map(symbol))
        let followedProfiles = profiles.filter { accounts.contains($0.id.lowercased()) }
        let earliest = now.addingTimeInterval(-30 * 86_400)
        var events: [String: Self] = [:]
        func retain(_ event: Self) {
            guard event.tracked || event.held || event.isFollow, event.occurredAt >= earliest,
                  event.occurredAt <= now else { return }
            if let previous = events[event.id], previous.occurredAt > event.occurredAt { return }
            events[event.id] = event
        }
        for update in updates {
            let isTracked = accounts.contains(update.authorId.lowercased()) || followedProfiles.contains {
                platform($0.platform) == platform(update.platform) &&
                    $0.handle.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                        .caseInsensitiveCompare(update.authorName.trimmingCharacters(in: CharacterSet(charactersIn: "@"))) == .orderedSame
            }
            retain(.init(payload: .account(update), tracked: isTracked, held: held.contains(symbol(update.ticker))))
        }
        for movement in movements {
            retain(.init(payload: .money(movement), tracked: money.contains(movement.accountId.lowercased()),
                         held: held.contains(symbol(movement.ticker))))
        }
        for person in followers where person.profile.isValid {
            retain(.init(payload: .follower(person), tracked: false, held: false))
        }
        return Array(events.values.sorted {
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt > $1.occurredAt }
            return $0.id < $1.id
        }.prefix(200))
    }

    static func symbol(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
    private static func platform(_ value: String) -> String {
        value.lowercased() == "twitter" ? "x" : value.lowercased()
    }
}
