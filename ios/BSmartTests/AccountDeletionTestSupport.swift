import XCTest
@testable import BSmart

struct DeletionFixture {
    let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    let ticket = AccountDeletionTicket(id: UUID(), statusToken: String(repeating: "test-deletion_", count: 4))
    let endpoint = URL(string: "https://account.example.invalid/v1/auth/account/deletions")!
    let session: TradingAccountSession
    init(provider: AccountIdentityProvider = .google) {
        session = renewalSession(account: .init(id: UUID(), provider: provider))
    }
    func record(wallet: Bool = true) throws -> AccountDeletionRecord {
        try .init(account: session.account, endpoint: endpoint, ticket: ticket,
                  walletAddress: wallet ? PreflightTestFixture.wallet.address : nil,
                  googleUserID: session.account.provider == .google ? "disposable-google-id" : nil, now: now)
    }
    func receipt(completed: Bool = false, id: UUID? = nil, requestedAt: Date? = nil) throws -> AccountDeletionReceipt {
        let body: [String: Any] = ["id": (id ?? ticket.id).uuidString, "status": completed ? "completed" : "pending",
            "requestedAt": (requestedAt ?? now).ISO8601Format(),
            "completedAt": completed ? now.addingTimeInterval(1).ISO8601Format() as Any : NSNull(),
            "retryAfterSeconds": completed ? 0 : 30]
        return try BSmartJSONCoding.makeDecoder().decode(AccountDeletionReceipt.self,
            from: JSONSerialization.data(withJSONObject: body))
    }
}

@MainActor
final class DeletionMemoryStorage: AccountDeletionPersisting {
    var saved: AccountDeletionRecord?
    var failsLoad = false
    var rejectsStage: AccountDeletionRecord.Stage?
    var rejectsDisconnected = false
    var saves = 0
    init(_ record: AccountDeletionRecord? = nil) { saved = record }
    func load() throws -> AccountDeletionRecord? {
        if failsLoad { throw AccountDeletionError.storage }
        return saved
    }
    func save(_ record: AccountDeletionRecord) throws {
        if record.stage == rejectsStage || (rejectsDisconnected && record.providerDisconnected) {
            throw AccountDeletionError.storage
        }
        if let saved { try record.validateSuccessor(of: saved) }
        saved = record; saves += 1
    }
    func clear(ticket: AccountDeletionTicket) throws {
        guard saved?.ticket == ticket, saved?.stage == .prepared || saved?.stage == .completed else {
            throw AccountDeletionError.storage
        }
        saved = nil
    }
}

@MainActor
final class DeletionTestCleanup: AccountDeletionLocalCleanup {
    var suspensions: [TradingAccountIdentity] = []
    var removals: [TradingAccountIdentity] = []
    var failSuspend = false
    var failRemove = false
    func suspendAccount(_ identity: TradingAccountIdentity) throws {
        suspensions.append(identity)
        if failSuspend { throw AccountDeletionError.storage }
    }
    func removeAccountData(_ identity: TradingAccountIdentity) async throws {
        removals.append(identity)
        if failRemove { throw AccountDeletionError.storage }
    }
}

@MainActor
final class DeletionTestGoogle: GoogleAccountDisconnecting {
    var users: [String] = []
    var failure: Error?
    func disconnect(userID: String) async throws {
        users.append(userID)
        if let failure { throw failure }
    }
}

@MainActor
final class DeletionTestClient: AccountDeleting {
    var requests: [AccountDeletionRequest] = []
    var queries: [AccountDeletionTicket] = []
    var requestResult: Result<AccountDeletionReceipt, Error>
    var statusResult: Result<AccountDeletionReceipt, Error>
    var onRequest: (() async throws -> AccountDeletionReceipt)?
    var onStatus: (() async throws -> AccountDeletionReceipt)?
    init(_ fixture: DeletionFixture) throws {
        requestResult = .success(try fixture.receipt())
        statusResult = .success(try fixture.receipt(completed: true))
    }
    func requestAccountDeletion(_ request: AccountDeletionRequest, accountToken: String) async throws -> AccountDeletionReceipt {
        requests.append(request)
        if let onRequest { return try await onRequest() }
        return try requestResult.get()
    }
    func accountDeletionStatus(ticket: AccountDeletionTicket) async throws -> AccountDeletionReceipt {
        queries.append(ticket)
        if let onStatus { return try await onStatus() }
        return try statusResult.get()
    }
}

@MainActor
func deletionCoordinator(_ fixture: DeletionFixture, storage: DeletionMemoryStorage,
                         client: DeletionTestClient? = nil, cleanup: DeletionTestCleanup? = nil,
                         google: DeletionTestGoogle? = nil, now: (() -> Date)? = nil) -> AccountDeletionCoordinator {
    .init(client: client, storage: storage, cleanup: cleanup ?? DeletionTestCleanup(), google: google ?? DeletionTestGoogle(),
          endpoint: fixture.endpoint, now: now ?? { fixture.now })
}
