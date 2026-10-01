import Combine
import Foundation

@MainActor
final class ActivityNotificationStore: ObservableObject {
    @Published private(set) var items: [ActivityNotification] = [] {
        didSet { updateUnreadCount() }
    }
    @Published private(set) var readVersions: [String: Date] = [:] {
        didSet { updateUnreadCount() }
    }
    @Published private(set) var unreadCount = 0
    private let defaults: UserDefaults
    private var scope: String?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func activate(scope: String) {
        guard self.scope != scope else { return }
        self.scope = scope
        items = []
        readVersions = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
    }
    func replace(_ items: [ActivityNotification]) {
        if self.items != items { self.items = items }
    }
    func isRead(_ item: ActivityNotification) -> Bool {
        readVersions[item.id].map { $0 >= item.occurredAt } ?? false
    }
    func markRead(_ item: ActivityNotification) {
        guard items.contains(where: { $0.id == item.id }), !isRead(item) else { return }
        readVersions[item.id] = max(readVersions[item.id] ?? .distantPast, item.occurredAt)
        persist()
    }
    func markAllRead() {
        var next = readVersions
        for item in items { next[item.id] = max(next[item.id] ?? .distantPast, item.occurredAt) }
        guard next != readVersions else { return }
        readVersions = next
        persist()
    }
    private func updateUnreadCount() {
        let count = items.reduce(0) { $0 + (isRead($1) ? 0 : 1) }
        if unreadCount != count { unreadCount = count }
    }
    private var storageKey: String { "bsmart.activity-inbox.v1.\(scope ?? "guest")" }
    private func persist() {
        guard scope != nil else { return }
        if readVersions.count > 4_000 {
            readVersions = Dictionary(uniqueKeysWithValues: readVersions.sorted { $0.value > $1.value }.prefix(4_000).map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(readVersions) { defaults.set(data, forKey: storageKey) }
    }
}
