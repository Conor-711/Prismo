import Foundation
import Combine

@MainActor
protocol AccountDeletionLocalCleanup {
    func suspendAccount(_ identity: TradingAccountIdentity) throws
    func removeAccountData(_ identity: TradingAccountIdentity) async throws
}

@MainActor
protocol GoogleAccountDisconnecting {
    func disconnect(userID: String) async throws
}

@MainActor
final class AccountDeletionCoordinator: ObservableObject {
    @Published private(set) var record: AccountDeletionRecord?
    @Published private(set) var isBusy = false
    @Published private(set) var error: AccountDeletionError?
    private let client: AccountDeleting?
    private let storage: AccountDeletionPersisting
    private let cleanup: AccountDeletionLocalCleanup
    private let google: GoogleAccountDisconnecting
    let endpoint: URL
    private let now: () -> Date

    init(client: AccountDeleting?, storage: AccountDeletionPersisting, cleanup: AccountDeletionLocalCleanup,
         google: GoogleAccountDisconnecting, endpoint: URL, now: @escaping () -> Date = Date.init) {
        self.client = client; self.storage = storage; self.cleanup = cleanup; self.google = google
        self.endpoint = endpoint; self.now = now
        do { try reload() } catch { self.error = .storage }
    }

    // Caller must freshly reauthenticate the same identity and verify recovery before entering here.
    func submit(_ candidate: AccountDeletionRecord, session: TradingAccountSession,
                confirmed: Bool, recoveryConfirmed: Bool) async throws {
        guard !isBusy else { throw AccountDeletionError.unavailable }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            try Task.checkCancellation()
            guard let client else { throw AccountDeletionError.unavailable }
            try candidate.validate()
            try session.validateReceipt(now: now())
            guard confirmed, recoveryConfirmed else { throw AccountDeletionError.confirmationRequired }
            guard candidate.stage == .prepared, candidate.account == session.account,
                  candidate.endpoint == endpoint, candidate.createdAt <= now(),
                  candidate.createdAt >= now().addingTimeInterval(-60) else { throw AccountDeletionError.accountChanged }
            try reload()
            guard record == nil else { throw AccountDeletionError.unavailable }
            try storage.save(candidate)
            record = candidate
            // Suspend app access before I/O, but never call the wallet vault's delete/reset APIs.
            try cleanup.suspendAccount(candidate.account)
            try Task.checkCancellation()
            var submitting = candidate
            try submitting.willSubmit()
            try persist(submitting)
            let receipt = try await client.requestAccountDeletion(.init(ticket: candidate.ticket,
                confirmDeletion: confirmed, walletRecoveryConfirmed: recoveryConfirmed), accountToken: session.accessToken)
            try receive(receipt, ticket: candidate.ticket)
            try Task.checkCancellation()
            try await finishLocalSteps(ticket: candidate.ticket)
        } catch {
            self.error = mapped(error)
            throw error
        }
    }

    func resume() async throws {
        guard !isBusy else { throw AccountDeletionError.unavailable }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            try Task.checkCancellation()
            try reload()
            guard let saved = record else { return }
            try cleanup.suspendAccount(saved.account)
            if saved.stage == .prepared || saved.stage == .completed { return }
            if saved.stage == .serverCompleted {
                try await finishLocalSteps(ticket: saved.ticket)
                return
            }
            guard let client else { throw AccountDeletionError.unavailable }
            if let next = saved.nextCheckAt, next > now() { return }
            let receipt = try await client.accountDeletionStatus(ticket: saved.ticket)
            // Preserve a received result even if the page was dismissed while the request completed.
            try receive(receipt, ticket: saved.ticket)
            try Task.checkCancellation()
            try await finishLocalSteps(ticket: saved.ticket)
        } catch {
            self.error = mapped(error)
            throw error
        }
    }

    func retryUnconfirmed(session: TradingAccountSession, googleUserID: String?, confirmed: Bool) async throws {
        guard !isBusy, confirmed else { throw AccountDeletionError.confirmationRequired }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            try Task.checkCancellation()
            guard let client else { throw AccountDeletionError.unavailable }
            try reload()
            guard let saved = record, saved.stage == .submitted, session.account == saved.account,
                  googleUserID == saved.googleUserID else { throw AccountDeletionError.accountChanged }
            try session.validateReceipt(now: now())
            try cleanup.suspendAccount(saved.account)
            do {
                let receipt = try await client.accountDeletionStatus(ticket: saved.ticket)
                try receive(receipt, ticket: saved.ticket)
                try Task.checkCancellation()
                try await finishLocalSteps(ticket: saved.ticket)
                return
            } catch AccountDeletionError.requestNotFound {
                // A deliberate fresh-auth retry uses the original id; never create a second request.
            }
            try Task.checkCancellation()
            let receipt = try await client.requestAccountDeletion(.init(ticket: saved.ticket,
                confirmDeletion: true, walletRecoveryConfirmed: true), accountToken: session.accessToken)
            try receive(receipt, ticket: saved.ticket)
            try Task.checkCancellation()
            try await finishLocalSteps(ticket: saved.ticket)
        } catch { self.error = mapped(error); throw error }
    }

    func acknowledgeOrDiscardPrepared(ticket: AccountDeletionTicket) throws {
        guard !isBusy else { throw AccountDeletionError.unavailable }
        do {
            try reload()
            guard let current = record, current.ticket == ticket,
                  current.stage == .prepared || current.stage == .completed else { throw AccountDeletionError.storage }
            try storage.clear(ticket: ticket)
            record = nil; error = nil
        } catch { self.error = mapped(error); throw error }
    }

    private func receive(_ receipt: AccountDeletionReceipt, ticket: AccountDeletionTicket) throws {
        var current = try current(ticket)
        try current.received(receipt, now: now())
        try persist(current)
    }

    private func finishLocalSteps(ticket: AccountDeletionTicket) async throws {
        var current = try current(ticket)
        guard current.stage == .serverCompleted else { return }
        try Task.checkCancellation()
        // Local personal data must not remain indefinitely when provider disconnect is unavailable.
        try await cleanup.removeAccountData(current.account)
        try Task.checkCancellation()
        if !current.providerDisconnected {
            guard let userID = current.googleUserID else { throw AccountDeletionError.invalidResponse }
            try await google.disconnect(userID: userID)
            current = try self.current(ticket)
            try current.finishedProviderDisconnect()
            try persist(current)
        }
        try Task.checkCancellation()
        current = try self.current(ticket)
        try current.finishedLocalCleanup()
        try persist(current)
    }

    private func current(_ ticket: AccountDeletionTicket) throws -> AccountDeletionRecord {
        try reload()
        guard let current = record, current.ticket == ticket else { throw AccountDeletionError.accountChanged }
        return current
    }

    private func persist(_ next: AccountDeletionRecord) throws {
        try next.validateSuccessor(of: current(next.ticket))
        try storage.save(next)
        record = next
    }

    private func reload() throws {
        let loaded = try storage.load()
        if let loaded {
            try loaded.validate()
            guard loaded.endpoint == endpoint else { throw AccountDeletionError.accountChanged }
        }
        record = loaded
    }

    private func mapped(_ error: Error) -> AccountDeletionError? {
        if error is CancellationError { return nil }
        return error as? AccountDeletionError ?? .unavailable
    }
}
