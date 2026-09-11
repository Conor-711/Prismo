import Foundation
import Security

@MainActor
protocol AccountDeletionPersisting {
    func load() throws -> AccountDeletionRecord?
    func save(_ record: AccountDeletionRecord) throws
    func clear(ticket: AccountDeletionTicket) throws
}

@MainActor
final class KeychainAccountDeletionStore: AccountDeletionPersisting {
    private let service: String
    init(service: String = Bundle.main.bundleIdentifier ?? "today.bsmart.ios") {
        self.service = service + ".account-deletion.v1"
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "request", kSecAttrSynchronizable as String: false]
    }

    func load() throws -> AccountDeletionRecord? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, data.count <= 16384 else { throw AccountDeletionError.storage }
        do {
            let record = try JSONDecoder().decode(AccountDeletionRecord.self, from: data)
            try record.validate()
            return record
        } catch { throw AccountDeletionError.storage }
    }

    func save(_ record: AccountDeletionRecord) throws {
        try record.validate()
        let current = try load()
        if let current { try record.validateSuccessor(of: current) }
        else if record.stage != .prepared { throw AccountDeletionError.storage }
        let data = try JSONEncoder().encode(record)
        guard data.count <= 16384 else { throw AccountDeletionError.storage }
        let values: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        // Main-actor, single-app-process ownership. Never replace a failed read with a new ticket.
        let status = current == nil ? SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
            : SecItemUpdate(query as CFDictionary, values as CFDictionary)
        guard status == errSecSuccess else { throw AccountDeletionError.storage }
    }

    func clear(ticket: AccountDeletionTicket) throws {
        guard let current = try load() else { return }
        guard current.ticket == ticket, current.stage == .prepared || current.stage == .completed else {
            throw AccountDeletionError.storage
        }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AccountDeletionError.storage }
    }
}
