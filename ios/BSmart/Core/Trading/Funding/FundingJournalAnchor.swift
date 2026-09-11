import Foundation
import Security
import CryptoKit

struct FundingJournalCheckpoint: Codable, Equatable {
    let sequence: UInt64
    let digest: Data
    static let empty = Self(sequence: 0, digest: Data(count: 32))
}

struct FundingJournalAnchor: Codable {
    let version: Int
    let id: UUID
    let key: Data
    var committed: FundingJournalCheckpoint
    var pending: FundingJournalCheckpoint?

    static func create() -> Self {
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        return .init(version: 1, id: UUID(), key: key, committed: .empty, pending: nil)
    }

    func validate() throws {
        guard version == 1, key.count == 32, committed.digest.count == 32,
              committed.sequence <= FundingJournalDatabase.maximumEvents,
              committed.sequence > 0 || committed == .empty else { throw FundingJournalError.integrity }
        if let pending {
            guard pending.sequence == committed.sequence + 1, pending.digest.count == 32 else { throw FundingJournalError.integrity }
        }
    }
}

struct FundingJournalAnchorStore: Sendable {
    let service: String
    let keychain: WalletKeychainAccess

    func load() throws -> FundingJournalAnchor? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = keychain.read(request)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data, data.count <= 2_048 else { throw FundingJournalError.unavailable }
        do {
            let anchor = try JSONDecoder().decode(FundingJournalAnchor.self, from: data)
            try anchor.validate()
            return anchor
        } catch { throw FundingJournalError.integrity }
    }

    func insert(_ anchor: FundingJournalAnchor) throws {
        var request = query
        request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        request[kSecValueData as String] = try JSONEncoder().encode(anchor)
        guard keychain.add(request) == errSecSuccess else { throw FundingJournalError.unavailable }
    }

    func save(_ anchor: FundingJournalAnchor) throws {
        try anchor.validate()
        guard keychain.update(query, values: [kSecValueData as String: try JSONEncoder().encode(anchor)]) == errSecSuccess else {
            throw FundingJournalError.unavailable
        }
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service + ".funding-journal.v1",
         kSecAttrAccount as String: "ledger", kSecAttrSynchronizable as String: false]
    }
}

enum FundingJournalCryptography {
    static func seal(_ record: FundingJournalRecord, anchor: FundingJournalAnchor) throws -> (Data, FundingJournalCheckpoint) {
        try sealEvent(.source(record), anchor: anchor)
    }

    static func sealEvent(_ event: FundingJournalEvent, anchor: FundingJournalAnchor) throws -> (Data, FundingJournalCheckpoint) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(event)
        guard data.count <= 16_384 else { throw FundingJournalError.capacity }
        let aad = associatedData(anchor)
        guard let sealed = try AES.GCM.seal(data, using: SymmetricKey(data: anchor.key), authenticating: aad).combined else {
            throw FundingJournalError.unavailable
        }
        return (sealed, .init(sequence: anchor.committed.sequence + 1, digest: Data(SHA256.hash(data: aad + sealed))))
    }

    static func open(_ sealed: Data, checkpoint: FundingJournalCheckpoint, anchor: FundingJournalAnchor) throws -> FundingJournalRecord {
        guard case .source(let record) = try openEvent(sealed, checkpoint: checkpoint, anchor: anchor) else {
            throw FundingJournalError.integrity
        }
        return record
    }

    static func openEvent(_ sealed: Data, checkpoint: FundingJournalCheckpoint, anchor: FundingJournalAnchor) throws -> FundingJournalEvent {
        guard sealed.count <= 16_412, checkpoint.sequence == anchor.committed.sequence + 1 else { throw FundingJournalError.integrity }
        let aad = associatedData(anchor)
        guard checkpoint.digest == Data(SHA256.hash(data: aad + sealed)) else { throw FundingJournalError.integrity }
        do {
            let plaintext = try AES.GCM.open(.init(combined: sealed), using: SymmetricKey(data: anchor.key), authenticating: aad)
            return try JSONDecoder().decode(FundingJournalEvent.self, from: plaintext)
        } catch { throw FundingJournalError.integrity }
    }

    private static func associatedData(_ anchor: FundingJournalAnchor) -> Data {
        Data("bSmart funding journal v1|\(anchor.id.uuidString.lowercased())|\(anchor.committed.sequence + 1)|".utf8)
            + anchor.committed.digest
    }
}
