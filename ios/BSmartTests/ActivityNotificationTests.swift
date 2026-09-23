import XCTest
@testable import BSmart

@MainActor
final class ActivityNotificationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testMatchingBothReasonsDoesNotDuplicateAndKeepsIndividualEvents() {
        let first = update(age: 10), second = update(age: 20)
        let items = build([first, first, second], [movement()], accounts: ["AUTHOR"], held: [" nvda "])
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.filter(\.tracked).count, 2)
        XCTAssertEqual(items.filter(\.held).count, 3)
        XCTAssertEqual(items.first?.id, "account:\(first.id)")
    }

    func testFollowedMoneyAndHeldOpinionsAreIncludedButUnrelatedEventsAreNot() {
        XCTAssertEqual(build([update()], [movement()], money: ["WALLET"]).count, 1)
        XCTAssertEqual(build([update()], [], held: ["NvDa"]).count, 1)
        XCTAssertTrue(build([update()], [movement()], held: ["BTC"]).isEmpty)
        XCTAssertTrue(build([update()], [movement()]).isEmpty)
    }

    func testSourceNamespacesPreventIDCollision() {
        let id = UUID()
        XCTAssertEqual(build([update(id: id)], [movement(id: id)], held: ["NVDA"]).count, 2)
    }

    func testDateWindowExcludesExpiredAndFutureEvents() {
        let boundary = update(age: 30 * 86_400)
        let result = build([boundary, update(age: 30 * 86_400 + 1), update(age: -1)], [], held: ["NVDA"])
        XCTAssertEqual(result.map(\.id), ["account:\(boundary.id)"])
    }

    func testNewestRevisionWinsAndOrderIsStableWithBoundedHistory() {
        let id = UUID()
        let rows = (0..<220).map { update(age: Double($0)) }
        let first = build(rows + [update(id: id, age: 999), update(id: id, age: 1)], [], held: ["NVDA"])
        let reversed = build(Array(rows.reversed()) + [update(id: id, age: 1), update(id: id, age: 999)], [], held: ["NVDA"])
        XCTAssertEqual(first, reversed)
        XCTAssertEqual(first.count, 200)
        XCTAssertEqual(first.first(where: { $0.id == "account:\(id)" })?.occurredAt, now.addingTimeInterval(-1))
    }

    func testLegacyHandleMatchRequiresSamePlatform() {
        let profile = SmartAccountProfile(id: "legacy", name: "Investor", handle: "@author", platform: "Twitter",
            score: 100, scoreChange: 0, specialty: "Tech", horizon: "20D", recentTicker: "NVDA")
        let result = ActivityNotification.build(updates: [update(), update(platform: "YouTube")], movements: [],
            followedAccounts: ["legacy"], followedMoney: [], heldTickers: [], profiles: [profile], now: now)
        XCTAssertEqual(result.count, 1)
    }

    func testReadStatePersistsAndIsIsolatedByAccount() throws {
        let suite = "notification-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ActivityNotificationStore(defaults: defaults)
        let items = build([update(), update(age: 20)], [], held: ["NVDA"])
        store.activate(scope: "A"); store.replace(items)
        XCTAssertEqual(store.unreadCount, 2)
        store.markRead(items[0])
        XCTAssertEqual(store.unreadCount, 1)
        let restored = ActivityNotificationStore(defaults: defaults)
        restored.activate(scope: "A"); restored.replace(items)
        XCTAssertEqual(restored.unreadCount, 1)
        restored.activate(scope: "B")
        XCTAssertTrue(restored.items.isEmpty)
        restored.replace(items)
        XCTAssertEqual(restored.unreadCount, 2)
        restored.activate(scope: "A"); restored.replace(items)
        XCTAssertEqual(restored.unreadCount, 1)
    }

    func testMarkAllDoesNotReadFutureArrivalsOrNewerRevisions() throws {
        let suite = "notification-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ActivityNotificationStore(defaults: defaults)
        let id = UUID()
        store.activate(scope: "A")
        store.replace(build([update(id: id, age: 20)], [], held: ["NVDA"]))
        store.markAllRead()
        XCTAssertEqual(store.unreadCount, 0)
        store.replace(build([update(id: id, age: 10), update(age: 1)], [], held: ["NVDA"]))
        XCTAssertEqual(store.unreadCount, 2)
        store.replace([])
        XCTAssertEqual(store.unreadCount, 0)
    }

    func testFollowersJoinAllNotificationsWithoutBecomingTrackedOrHeldActivity() {
        let profile = FeedPublicProfile(id: UUID(), nickname: "Alice", avatarURL: nil, handle: "alice")
        let latest = SocialPerson(profile: profile, at: now.addingTimeInterval(-10))
        let result = ActivityNotification.build(updates: [update(age: 20)], movements: [],
            followedAccounts: [], followedMoney: [], heldTickers: ["NVDA"],
            followers: [latest, latest, .init(profile: profile, at: now.addingTimeInterval(-100))], now: now)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.id, "follower:\(profile.id)")
        XCTAssertEqual(result.first?.occurredAt, latest.at)
        XCTAssertEqual(result.filter(\.isFollow).count, 1)
        XCTAssertFalse(result[0].tracked)
        XCTAssertFalse(result[0].held)
        let excluded = ActivityNotification.build(updates: [], movements: [], followedAccounts: [],
            followedMoney: [], heldTickers: [], followers: [
                .init(profile: profile, at: now.addingTimeInterval(-30 * 86_400 - 1)),
                .init(profile: profile, at: now.addingTimeInterval(1))], now: now)
        XCTAssertTrue(excluded.isEmpty)
    }

    func testFollowReadStateSurvivesProfileChangesAndResetsOnNewFollowOrAccount() throws {
        let suite = "follow-notification-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ActivityNotificationStore(defaults: defaults)
        let id = UUID()
        func event(_ name: String, age: TimeInterval) -> ActivityNotification {
            .init(payload: .follower(.init(profile: .init(id: id, nickname: name, avatarURL: nil, handle: "alice"),
                at: now.addingTimeInterval(-age))), tracked: false, held: false)
        }
        store.activate(scope: "A"); store.replace([event("Alice", age: 20)])
        store.markAllRead()
        store.replace([event("New name", age: 20)])
        XCTAssertEqual(store.unreadCount, 0)
        store.replace([event("New name", age: 10)])
        XCTAssertEqual(store.unreadCount, 1)
        store.activate(scope: "B")
        XCTAssertTrue(store.items.isEmpty)
        store.replace([event("Alice", age: 20)])
        XCTAssertEqual(store.unreadCount, 1)
        store.activate(scope: "A"); store.replace([event("Alice", age: 20)])
        XCTAssertEqual(store.unreadCount, 0)
    }

    private func build(_ updates: [SmartAccountUpdate], _ movements: [SmartMoneyMovement],
                       accounts: Set<String> = [], money: Set<String> = [], held: Set<String> = []) -> [ActivityNotification] {
        ActivityNotification.build(updates: updates, movements: movements, followedAccounts: accounts,
            followedMoney: money, heldTickers: held, now: now)
    }

    private func update(id: UUID = UUID(), age: TimeInterval = 100, platform: String = "X") -> SmartAccountUpdate {
        SmartAccountUpdate(id: id, ticker: "NVDA", companyName: "Nvidia", authorId: "author",
            authorName: "author", platform: platform, score: 120, platformPercentile: 0.1,
            direction: .bullish, lifecycle: .new, horizon: "20D", targetPrice: nil,
            thesis: "A source view", invalidation: nil, publishedAt: now.addingTimeInterval(-age), evidenceURL: nil)
    }
    private func movement(id: UUID = UUID()) -> SmartMoneyMovement {
        SmartMoneyMovement(id: id, ticker: "NVDA", companyName: "Nvidia", accountId: "wallet",
            accountLabel: "wallet", accountScore: 80, market: "xyz:NVDA", action: .reduced,
            direction: .bullish, notionalBefore: 1000, notionalAfter: 800, notionalChange: -200,
            leverage: nil, observedAt: now.addingTimeInterval(-100), evidenceURL: nil)
    }
}
