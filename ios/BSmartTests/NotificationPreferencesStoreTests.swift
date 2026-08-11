import XCTest
@testable import BSmart

final class NotificationPreferencesStoreTests: XCTestCase {
    @MainActor
    func testPreferencesMigratePersistAndNormalizeTickerSymbols() throws {
        let suiteName = "BSmartTests.NotificationPreferences.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: "bsmart.notifications.instant")
        defaults.set(false, forKey: "bsmart.notifications.digest")
        defaults.set(true, forKey: "bsmart.notifications.quiet-hours")

        let store = NotificationPreferencesStore(defaults: defaults)
        XCTAssertFalse(store.preferences.instantAlertsEnabled)
        XCTAssertFalse(store.preferences.dailyDigestEnabled)
        XCTAssertTrue(store.preferences.quietHoursEnabled)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let digestDate = try XCTUnwrap(calendar.date(from: DateComponents(hour: 9, minute: 15)))
        let quietStart = try XCTUnwrap(calendar.date(from: DateComponents(hour: 23, minute: 30)))
        let quietEnd = try XCTUnwrap(calendar.date(from: DateComponents(hour: 6, minute: 45)))

        store.setInstantAlertsEnabled(true)
        store.setDailyDigestEnabled(true)
        store.setDailyDigestTime(digestDate, calendar: calendar)
        store.setQuietHoursStart(quietStart, calendar: calendar)
        store.setQuietHoursEnd(quietEnd, calendar: calendar)
        store.setTicker("nvda", isEnabled: false)

        let restored = NotificationPreferencesStore(defaults: defaults)
        XCTAssertTrue(restored.preferences.instantAlertsEnabled)
        XCTAssertTrue(restored.preferences.dailyDigestEnabled)
        XCTAssertEqual(restored.preferences.dailyDigestMinutes, 9 * 60 + 15)
        XCTAssertEqual(restored.preferences.quietHoursStartMinutes, 23 * 60 + 30)
        XCTAssertEqual(restored.preferences.quietHoursEndMinutes, 6 * 60 + 45)
        XCTAssertFalse(restored.isTickerEnabled("NVDA"))
        XCTAssertFalse(restored.isTickerEnabled("nvda"))

        restored.setTicker("NvDa", isEnabled: true)
        XCTAssertTrue(NotificationPreferencesStore(defaults: defaults).isTickerEnabled("NVDA"))
    }

    @MainActor
    func testResetLocalPreferencesRestoresDefaultsAndRemovesLegacyValues() throws {
        let suiteName = "BSmartTests.NotificationPreferences.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: "bsmart.notifications.instant")
        defaults.set(false, forKey: "bsmart.notifications.digest")
        defaults.set(false, forKey: "bsmart.notifications.quiet-hours")
        let store = NotificationPreferencesStore(defaults: defaults)
        store.setTicker("NVDA", isEnabled: false)

        store.resetLocalPreferences()

        XCTAssertEqual(store.preferences, NotificationPreferences())
        XCTAssertNil(defaults.object(forKey: "bsmart.notification-preferences.v2"))
        XCTAssertNil(defaults.object(forKey: "bsmart.notifications.instant"))
        XCTAssertNil(defaults.object(forKey: "bsmart.notifications.digest"))
        XCTAssertNil(defaults.object(forKey: "bsmart.notifications.quiet-hours"))
    }
}
