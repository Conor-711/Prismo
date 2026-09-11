import Foundation
import Security

protocol AccountSessionPersisting {
    func load() throws -> TradingAccountSession?
    func save(_ session: TradingAccountSession) throws
    func clear() throws
    func beginRenewal(_ session: TradingAccountSession) throws
    func isRenewalPending() throws -> Bool
    func appleUserID(for session: TradingAccountSession) throws -> String?
    func save(_ session: TradingAccountSession, appleUserID: String?) throws
    func completeRenewal(_ session: TradingAccountSession, replacing previous: TradingAccountSession) throws
}

extension AccountSessionPersisting {
    func beginRenewal(_ session: TradingAccountSession) throws { throw AccountAccessError.storage }
    func isRenewalPending() throws -> Bool { false }
    func appleUserID(for session: TradingAccountSession) throws -> String? { nil }
    func save(_ session: TradingAccountSession, appleUserID: String?) throws {
        guard appleUserID == nil else { throw AccountAccessError.storage }
        try save(session)
    }
    func completeRenewal(_ session: TradingAccountSession, replacing previous: TradingAccountSession) throws {
        guard try isRenewalPending(), try load()?.hasSameCredentials(as: previous) == true else { throw AccountAccessError.storage }
        try save(session)
    }
}

struct AccountSessionEnvelope: Codable, CustomStringConvertible, CustomDebugStringConvertible {
    let version: Int
    let session: TradingAccountSession
    let renewalPending: Bool
    let appleUserID: String?
    var description: String { "AccountSessionEnvelope(redacted)" }
    var debugDescription: String { description }

    init(session: TradingAccountSession, renewalPending: Bool, appleUserID: String? = nil) {
        version = 3; self.session = session; self.renewalPending = renewalPending; self.appleUserID = appleUserID
    }

    func validateReference() throws {
        if let appleUserID {
            guard version == 3, session.account.provider == .apple,
                  (1...255).contains(appleUserID.utf8.count), appleUserID.utf8.allSatisfy({ (33...126).contains($0) }) else {
                throw AccountAccessError.storage
            }
        }
    }

    static func decode(_ data: Data) throws -> Self {
        struct Header: Decodable { let version: Int? }
        let decoder = BSmartJSONCoding.makeDecoder()
        if let version = try decoder.decode(Header.self, from: data).version {
            guard version == 2 || version == 3 else { throw AccountAccessError.storage }
            let record = try decoder.decode(Self.self, from: data)
            try record.validateReference()
            return record
        }
        return Self(session: try decoder.decode(TradingAccountSession.self, from: data), renewalPending: false)
    }
}

final class KeychainAccountSessionStore: AccountSessionPersisting {
    private let service: String

    init(service: String) { self.service = service + ".trading-identity.v1" }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "session", kSecAttrSynchronizable as String: false]
    }

    func load() throws -> TradingAccountSession? {
        try record()?.session
    }

    func isRenewalPending() throws -> Bool { try record()?.renewalPending ?? false }

    func appleUserID(for session: TradingAccountSession) throws -> String? {
        guard let current = try record(), current.session.hasSameCredentials(as: session) else { throw AccountAccessError.storage }
        return current.appleUserID
    }

    func beginRenewal(_ session: TradingAccountSession) throws {
        guard let current = try record(), !current.renewalPending, current.session.hasSameCredentials(as: session) else {
            throw AccountAccessError.storage
        }
        try write(.init(session: current.session, renewalPending: true, appleUserID: current.appleUserID))
    }

    func completeRenewal(_ session: TradingAccountSession, replacing previous: TradingAccountSession) throws {
        guard let current = try record(), current.renewalPending, current.session.hasSameCredentials(as: previous),
              session.account == previous.account, session.accessToken != previous.accessToken else {
            throw AccountAccessError.storage
        }
        try write(.init(session: session, renewalPending: false, appleUserID: current.appleUserID))
    }

    private func record() throws -> AccountSessionEnvelope? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw AccountAccessError.storage }
        return try AccountSessionEnvelope.decode(data)
    }

    func save(_ session: TradingAccountSession) throws {
        try save(session, appleUserID: nil)
    }

    func save(_ session: TradingAccountSession, appleUserID: String?) throws {
        try write(.init(session: session, renewalPending: false, appleUserID: appleUserID))
    }

    private func write(_ record: AccountSessionEnvelope) throws {
        try record.validateReference()
        let encoder = BSmartJSONCoding.makeEncoder()
        // Keychain-only format: preserve precision; the shared decoder also reads legacy ISO dates.
        encoder.dateEncodingStrategy = .deferredToDate
        let data = try encoder.encode(record)
        let values = [kSecValueData as String: data,
                      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as [String: Any]
        let updated = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw AccountAccessError.storage }
        let attributes = query.merging(values) { _, new in new }
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw AccountAccessError.storage }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AccountAccessError.storage }
    }
}
