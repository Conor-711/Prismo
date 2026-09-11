import Foundation

// This transport is not an authorization to erase local wallet material.
protocol AccountDeleting: Sendable {
    func requestAccountDeletion(_ request: AccountDeletionRequest, accountToken: String) async throws -> AccountDeletionReceipt
    func accountDeletionStatus(ticket: AccountDeletionTicket) async throws -> AccountDeletionReceipt
}

extension HTTPAccountAuthClient: AccountDeleting {
    func requestAccountDeletion(_ input: AccountDeletionRequest, accountToken: String) async throws -> AccountDeletionReceipt {
        try Task.checkCancellation()
        try input.validate()
        guard TradingAccountSession.validToken(accountToken) else { throw AccountDeletionError.unauthorized }
        return try await deletionRequest("account/deletions", body: input, ticket: input.ticket,
                                         token: accountToken, expectedStatus: 202)
    }

    func accountDeletionStatus(ticket: AccountDeletionTicket) async throws -> AccountDeletionReceipt {
        try Task.checkCancellation()
        try ticket.validate()
        struct Input: Encodable { let statusToken: String }
        let installation: String
        do { installation = try await installationAccessToken() }
        catch is CancellationError { throw CancellationError() }
        catch { throw AccountDeletionError.unavailable }
        return try await deletionRequest("account/deletions/\(ticket.id.uuidString)/status",
            body: Input(statusToken: ticket.statusToken), ticket: ticket, token: installation, expectedStatus: 200)
    }

    private func deletionRequest<Body: Encodable>(_ path: String, body: Body, ticket: AccountDeletionTicket,
                                                 token: String, expectedStatus: Int) async throws -> AccountDeletionReceipt {
        do {
            try Task.checkCancellation()
            let data = try await request(path, method: "POST", body: JSONEncoder().encode(body), token: token,
                expectedStatus: expectedStatus, statusErrors: [401: AccountDeletionError.unauthorized,
                    404: expectedStatus == 200 ? AccountDeletionError.requestNotFound : AccountDeletionError.unavailable,
                    409: AccountDeletionError.reauthenticationRequired,
                    422: AccountDeletionError.invalidResponse, 429: AccountDeletionError.unavailable,
                    503: AccountDeletionError.unavailable])
            try Task.checkCancellation()
            let receipt: AccountDeletionReceipt
            do { receipt = try BSmartJSONCoding.makeDecoder().decode(AccountDeletionReceipt.self, from: data) }
            catch { throw AccountDeletionError.invalidResponse }
            try receipt.validate(for: ticket)
            return receipt
        } catch is CancellationError { throw CancellationError() }
        catch let error as AccountDeletionError { throw error }
        catch AccountAccessError.invalidResponse { throw AccountDeletionError.invalidResponse }
        catch { throw AccountDeletionError.unavailable }
    }
}
