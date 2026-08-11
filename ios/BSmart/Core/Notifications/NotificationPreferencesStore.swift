import Combine
import Foundation

struct NotificationPreferences: Codable, Equatable {
    var instantAlertsEnabled = true
    var dailyDigestEnabled = true
    var dailyDigestMinutes = 8 * 60
    var quietHoursEnabled = true
    var quietHoursStartMinutes = 22 * 60
    var quietHoursEndMinutes = 7 * 60
    var mutedTickers: Set<String> = []
}

@MainActor
final class NotificationPreferencesStore: ObservableObject {
    @Published private(set) var preferences: NotificationPreferences

    private let defaults: UserDefaults
    private let syncCoordinator: BSmartSyncCoordinator?
    private let storageKey = "bsmart.notification-preferences.v2"

    init(
        defaults: UserDefaults = .standard,
        syncCoordinator: BSmartSyncCoordinator? = nil
    ) {
        self.defaults = defaults
        self.syncCoordinator = syncCoordinator

        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(NotificationPreferences.self, from: data) {
            preferences = saved
        } else {
            preferences = NotificationPreferences(
                instantAlertsEnabled: defaults.object(forKey: "bsmart.notifications.instant") as? Bool ?? true,
                dailyDigestEnabled: defaults.object(forKey: "bsmart.notifications.digest") as? Bool ?? true,
                quietHoursEnabled: defaults.object(forKey: "bsmart.notifications.quiet-hours") as? Bool ?? true
            )
        }
    }

    func setInstantAlertsEnabled(_ isEnabled: Bool) {
        update { $0.instantAlertsEnabled = isEnabled }
    }

    func setDailyDigestEnabled(_ isEnabled: Bool) {
        update { $0.dailyDigestEnabled = isEnabled }
    }

    func setDailyDigestTime(_ date: Date, calendar: Calendar = .current) {
        update { $0.dailyDigestMinutes = Self.minutesSinceMidnight(for: date, calendar: calendar) }
    }

    func setQuietHoursEnabled(_ isEnabled: Bool) {
        update { $0.quietHoursEnabled = isEnabled }
    }

    func setQuietHoursStart(_ date: Date, calendar: Calendar = .current) {
        update { $0.quietHoursStartMinutes = Self.minutesSinceMidnight(for: date, calendar: calendar) }
    }

    func setQuietHoursEnd(_ date: Date, calendar: Calendar = .current) {
        update { $0.quietHoursEndMinutes = Self.minutesSinceMidnight(for: date, calendar: calendar) }
    }

    func isTickerEnabled(_ ticker: String) -> Bool {
        !preferences.mutedTickers.contains(ticker.uppercased())
    }

    func setTicker(_ ticker: String, isEnabled: Bool) {
        let normalizedTicker = ticker.uppercased()
        update { preferences in
            if isEnabled {
                preferences.mutedTickers.remove(normalizedTicker)
            } else {
                preferences.mutedTickers.insert(normalizedTicker)
            }
        }
    }

    func date(for minutes: Int, calendar: Calendar = .current, referenceDate: Date = Date()) -> Date {
        let startOfDay = calendar.startOfDay(for: referenceDate)
        return calendar.date(byAdding: .minute, value: minutes, to: startOfDay) ?? referenceDate
    }

    func synchronize() async {
        await syncCoordinator?.enqueueNotificationPreferences(preferences)
    }

    func resetLocalPreferences() {
        preferences = NotificationPreferences()
        [
            storageKey,
            "bsmart.notifications.instant",
            "bsmart.notifications.digest",
            "bsmart.notifications.quiet-hours"
        ].forEach(defaults.removeObject(forKey:))
    }

    private func update(_ change: (inout NotificationPreferences) -> Void) {
        var updated = preferences
        change(&updated)
        preferences = updated
        persist()
        guard let syncCoordinator else { return }
        Task { await syncCoordinator.enqueueNotificationPreferences(updated) }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func minutesSinceMidnight(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
