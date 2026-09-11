import Foundation

struct AccountDeletionTicket: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let id: UUID
    let statusToken: String

    var description: String { "AccountDeletionTicket(redacted)" }
    var debugDescription: String { description }

    func validate() throws {
        guard TradingAccountSession.validToken(statusToken) else { throw AccountDeletionError.invalidResponse }
    }
}

struct AccountDeletionRequest: Encodable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let ticket: AccountDeletionTicket
    let confirmDeletion: Bool
    let walletRecoveryConfirmed: Bool

    var description: String { "AccountDeletionRequest(redacted)" }
    var debugDescription: String { description }

    func validate() throws {
        try ticket.validate()
        guard confirmDeletion, walletRecoveryConfirmed else { throw AccountDeletionError.confirmationRequired }
    }

    private enum CodingKeys: String, CodingKey { case id, statusToken, confirmDeletion, walletRecoveryConfirmed }

    func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(ticket.id, forKey: .id)
        try values.encode(ticket.statusToken, forKey: .statusToken)
        try values.encode(confirmDeletion, forKey: .confirmDeletion)
        try values.encode(walletRecoveryConfirmed, forKey: .walletRecoveryConfirmed)
    }
}

struct AccountDeletionReceipt: Decodable, Equatable, Sendable {
    enum Status: String, Decodable, Sendable { case pending, completed }
    let id: UUID
    let status: Status
    let requestedAt: Date
    let completedAt: Date?
    let retryAfterSeconds: Int

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, status, requestedAt, completedAt, retryAfterSeconds
    }

    private struct Field: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: Field.self)
        guard Set(fields.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)) else {
            throw AccountDeletionError.invalidResponse
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        status = try values.decode(Status.self, forKey: .status)
        requestedAt = try values.decode(Date.self, forKey: .requestedAt)
        completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
        retryAfterSeconds = try values.decode(Int.self, forKey: .retryAfterSeconds)
        guard requestedAt.timeIntervalSince1970.isFinite, requestedAt.timeIntervalSince1970 > 0 else {
            throw AccountDeletionError.invalidResponse
        }
        switch status {
        case .pending:
            guard completedAt == nil, (30...3600).contains(retryAfterSeconds) else {
                throw AccountDeletionError.invalidResponse
            }
        case .completed:
            guard let completedAt, completedAt.timeIntervalSince1970.isFinite,
                  completedAt >= requestedAt, retryAfterSeconds == 0 else {
                throw AccountDeletionError.invalidResponse
            }
        }
    }

    func validate(for ticket: AccountDeletionTicket, now: Date = Date()) throws {
        try ticket.validate()
        guard id == ticket.id, requestedAt <= now.addingTimeInterval(60),
              (completedAt ?? requestedAt) <= now.addingTimeInterval(60) else {
            throw AccountDeletionError.invalidResponse
        }
    }
}

enum AccountDeletionError: Error, Equatable {
    case confirmationRequired, reauthenticationRequired, unauthorized, requestNotFound, invalidResponse, unavailable
    case storage, accountChanged, providerDisconnectRequired
}
