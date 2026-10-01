import Foundation
import Combine

@MainActor
final class TradeThesisDraftStore: ObservableObject {
    static let shared = TradeThesisDraftStore()

    struct Key: Hashable { let accountID: UUID; let tradeID: UUID }
    @Published private(set) var failedKeys: Set<Key> = []
    private var memory: [Key: String] = [:]
    private var deletedAccounts: Set<UUID> = []
    private var pending: Task<Void, Never>?
    private let disk: ThesisDraftDisk

    init(directory: URL? = nil) {
        disk = ThesisDraftDisk(directory: directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TradeThesisDrafts", isDirectory: true))
    }

    func cached(accountID: UUID, tradeID: UUID) -> String? {
        memory[Key(accountID: accountID, tradeID: tradeID)]
    }

    func load(accountID: UUID, tradeID: UUID) async throws -> String {
        let key = Key(accountID: accountID, tradeID: tradeID)
        guard !deletedAccounts.contains(accountID) else { throw AccountDeletionError.accountChanged }
        if let value = memory[key] { return value }
        await pending?.value
        let value = try await disk.load(key)
        guard !deletedAccounts.contains(accountID) else { throw AccountDeletionError.accountChanged }
        // Input may have started while the protected file was being read.
        if let current = memory[key] { return current }
        memory[key] = value
        return value
    }

    func save(_ text: String, accountID: UUID, tradeID: UUID) {
        guard !deletedAccounts.contains(accountID) else { return }
        let key = Key(accountID: accountID, tradeID: tradeID)
        guard memory[key] != text else { return }
        memory[key] = text
        enqueue(key) { try await self.disk.save(text, key: key) }
    }

    func remove(accountID: UUID, tradeID: UUID) {
        let key = Key(accountID: accountID, tradeID: tradeID)
        memory[key] = ""
        enqueue(key) { try await self.disk.remove(key) }
    }

    func flush() async { await pending?.value }

    func erase(accountID: UUID) async throws {
        deletedAccounts.insert(accountID)
        memory = memory.filter { $0.key.accountID != accountID }
        await pending?.value
        try await disk.erase(accountID)
        failedKeys = failedKeys.filter { $0.accountID != accountID }
    }

    private func enqueue(_ key: Key, operation: @escaping @MainActor () async throws -> Void) {
        let previous = pending
        // Preserve edit/remove ordering without doing file I/O in the editor's binding.
        pending = Task {
            await previous?.value
            do {
                try await operation()
                if failedKeys.contains(key) { failedKeys.remove(key) }
            } catch { failedKeys.insert(key) }
        }
    }
}

private actor ThesisDraftDisk {
    let directory: URL
    init(directory: URL) { self.directory = directory }

    func load(_ key: TradeThesisDraftStore.Key) throws -> String {
        try requireActiveAccount(key.accountID)
        let url = location(key)
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 65_536 else { throw AccountAccessError.storage }
        return try JSONDecoder().decode(String.self, from: Data(contentsOf: url))
    }

    func save(_ text: String, key: TradeThesisDraftStore.Key) throws {
        try requireActiveAccount(key.accountID)
        let data = try JSONEncoder().encode(text)
        guard data.count <= 65_536 else { throw AccountAccessError.storage }
        try FileManager.default.createDirectory(at: location(key).deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: location(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func remove(_ key: TradeThesisDraftStore.Key) throws {
        let url = location(key)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    func erase(_ accountID: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: marker(accountID), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let folder = accountDirectory(accountID)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    private func requireActiveAccount(_ accountID: UUID) throws {
        if FileManager.default.fileExists(atPath: marker(accountID).path) { throw AccountAccessError.storage }
    }
    private func marker(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("deleted") }
    private func accountDirectory(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func location(_ key: TradeThesisDraftStore.Key) -> URL {
        accountDirectory(key.accountID).appendingPathComponent(key.tradeID.uuidString).appendingPathExtension("json")
    }
}
