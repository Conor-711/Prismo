import Foundation
import Security

struct AccountDeletionRecord: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    enum Stage: Int, Codable { case prepared, submitted, accepted, serverCompleted, completed }
    let version: Int
    let account: TradingAccountIdentity
    let endpoint: URL
    let ticket: AccountDeletionTicket
    let createdAt: Date
    let walletAddress: String?
    let googleUserID: String?
    private(set) var stage: Stage
    private(set) var requestedAt: Date?
    private(set) var completedAt: Date?
    private(set) var nextCheckAt: Date?
    private(set) var providerDisconnected: Bool

    var description: String { "AccountDeletionRecord(redacted)" }
    var debugDescription: String { description }

    init(account: TradingAccountIdentity, endpoint: URL, ticket: AccountDeletionTicket, walletAddress: String?,
         googleUserID: String?, now: Date = Date()) throws {
        version = 1; self.account = account; self.endpoint = endpoint; self.ticket = ticket
        self.walletAddress = walletAddress; self.googleUserID = googleUserID; createdAt = now; stage = .prepared
        providerDisconnected = account.provider == .apple
        try validate()
    }

    func validate() throws {
        try ticket.validate()
        guard version == 1, endpoint.scheme == "https", endpoint.host != nil, endpoint.user == nil,
              endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil,
              createdAt.timeIntervalSince1970.isFinite, createdAt.timeIntervalSince1970 > 0,
              walletAddress.map(TradingWalletChallenge.validAddress) ?? true else { throw AccountDeletionError.invalidResponse }
        if account.provider == .google {
            guard let googleUserID, (1...255).contains(googleUserID.utf8.count),
                  googleUserID.utf8.allSatisfy({ (33...126).contains($0) }) else { throw AccountDeletionError.invalidResponse }
        } else if googleUserID != nil { throw AccountDeletionError.invalidResponse }
        guard account.provider != .apple || providerDisconnected,
              stage != .completed || providerDisconnected,
              account.provider != .google || !providerDisconnected || stage.rawValue >= Stage.serverCompleted.rawValue else {
            throw AccountDeletionError.invalidResponse
        }
        if stage.rawValue >= Stage.accepted.rawValue {
            guard let requestedAt, requestedAt.timeIntervalSince1970.isFinite,
                  requestedAt >= createdAt.addingTimeInterval(-60) else { throw AccountDeletionError.invalidResponse }
        } else if requestedAt != nil || completedAt != nil { throw AccountDeletionError.invalidResponse }
        if stage.rawValue >= Stage.serverCompleted.rawValue {
            guard let completedAt, let requestedAt, completedAt.timeIntervalSince1970.isFinite,
                  completedAt >= requestedAt, nextCheckAt == nil else { throw AccountDeletionError.invalidResponse }
        } else if completedAt != nil { throw AccountDeletionError.invalidResponse }
        if let nextCheckAt {
            guard nextCheckAt.timeIntervalSince1970.isFinite, stage == .submitted || stage == .accepted else {
                throw AccountDeletionError.invalidResponse
            }
        }
    }

    mutating func willSubmit() throws {
        guard stage == .prepared else { throw AccountDeletionError.invalidResponse }
        stage = .submitted
    }

    mutating func received(_ receipt: AccountDeletionReceipt, now: Date = Date()) throws {
        try receipt.validate(for: ticket, now: now)
        guard stage != .prepared,
              requestedAt == nil || requestedAt == receipt.requestedAt,
              completedAt == nil || completedAt == receipt.completedAt,
              receipt.requestedAt >= createdAt.addingTimeInterval(-60) else { throw AccountDeletionError.invalidResponse }
        switch receipt.status {
        case .pending:
            guard stage == .submitted || stage == .accepted else { throw AccountDeletionError.invalidResponse }
            stage = .accepted
            nextCheckAt = now.addingTimeInterval(TimeInterval(receipt.retryAfterSeconds))
        case .completed:
            if stage != .completed { stage = .serverCompleted }
            completedAt = receipt.completedAt
            nextCheckAt = nil
        }
        requestedAt = receipt.requestedAt
        try validate()
    }

    mutating func finishedLocalCleanup() throws {
        guard stage == .serverCompleted, providerDisconnected else { throw AccountDeletionError.invalidResponse }
        stage = .completed
        try validate()
    }

    mutating func finishedProviderDisconnect() throws {
        guard stage == .serverCompleted else { throw AccountDeletionError.invalidResponse }
        providerDisconnected = true
        try validate()
    }

    func validateSuccessor(of previous: Self) throws {
        try previous.validate()
        try validate()
        let allowed: Bool
        switch previous.stage {
        case .prepared: allowed = stage == .prepared || stage == .submitted
        case .submitted: allowed = stage == .submitted || stage == .accepted || stage == .serverCompleted
        case .accepted: allowed = stage == .accepted || stage == .serverCompleted
        case .serverCompleted: allowed = stage == .serverCompleted || stage == .completed
        case .completed: allowed = stage == .completed
        }
        guard version == previous.version, account == previous.account, endpoint == previous.endpoint,
              ticket == previous.ticket, createdAt == previous.createdAt, walletAddress == previous.walletAddress,
              googleUserID == previous.googleUserID, allowed,
              stage != .completed || previous.providerDisconnected,
              !previous.providerDisconnected || providerDisconnected,
              previous.requestedAt == nil || requestedAt == previous.requestedAt,
              previous.completedAt == nil || completedAt == previous.completedAt else { throw AccountDeletionError.invalidResponse }
    }
}

extension AccountDeletionTicket {
    static func random() throws -> Self {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AccountDeletionError.storage }
        let secret = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return .init(id: UUID(), statusToken: secret)
    }
}
