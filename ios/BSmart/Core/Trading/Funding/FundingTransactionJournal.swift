import Foundation

enum FundingJournalCommitPhase: Sendable { case afterPendingAnchor, beforeCommit, afterCommit }

struct FundingAuthorizationPermit: Sendable {
    let id: UUID
    let plan: CCTPDepositPlan
    let authorizationHash: Data
    fileprivate init(_ record: FundingConsentRecord) throws {
        id = record.id
        plan = try record.plan.restored()
        authorizationHash = record.plan.authorizationHash
    }
}

struct FundingSigningPermit: Sendable {
    let intentID: UUID
    let accountID: UUID
    let owner: String
    let signingHash: Data
    let hasRecordedConsent: Bool
    fileprivate init(_ intent: FundingJournalIntent, consent: FundingConsentRecord?) {
        intentID = intent.id
        accountID = intent.accountID
        owner = intent.owner
        signingHash = intent.signingHash
        hasRecordedConsent = consent?.id == intent.id && consent?.state == .authorized
            && consent?.plan.matches(intent) == true && consent?.signature == intent.authorization
    }
}

final class FundingSubmissionPermit: @unchecked Sendable {
    let intentID: UUID
    let accountID: UUID
    let owner: String
    let chainID: Int
    let hash: String
    private let raw: Data
    private let check: FundingSubmissionCheck
    private let wallet: DeviceWalletSummary
    private let clock: @Sendable () -> Date
    private let hasRecordedConsent: Bool
    private let lock = NSLock()
    private var consumed = false

    fileprivate init(_ record: FundingJournalRecord, signed: FundingJournalRecord.Signed,
                     check: FundingSubmissionCheck, wallet: DeviceWalletSummary, consent: FundingConsentRecord?,
                     clock: @escaping @Sendable () -> Date) {
        intentID = record.intent.id
        accountID = record.intent.accountID
        owner = record.intent.owner
        chainID = record.intent.chainID
        hash = signed.hash
        raw = signed.raw
        self.check = check
        self.wallet = wallet
        self.clock = clock
        hasRecordedConsent = consent?.id == intentID && consent?.state == .authorized
            && consent?.plan.matches(record.intent) == true && consent?.signature == record.intent.authorization
    }

    // Consume and start the network task synchronously inside the revocable scope.
    // Copies of this reference share consumption; neither restart nor expiry recreates it.
    func start<T>(lease: FundingSigningLease, _ operation: (Data) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard !consumed else { throw FundingJournalError.invalidTransition }
        consumed = true
        guard hasRecordedConsent else { throw FundingJournalError.conflict }
        return try lease.perform(wallet: wallet) {
            try check.validate(hash: hash, wallet: wallet, now: clock())
            return try operation(raw)
        }
    }
}

actor FundingTransactionJournal: FundingHistoryAccessing, FundingSourceJournalAccessing, CCTPAttestationJournalAccessing, CCTPForwardJournalAccessing {
    private let files: FundingJournalFiles
    private let anchors: FundingJournalAnchorStore
    let clock: @Sendable () -> Date
    private let commitProbe: @Sendable (FundingJournalCommitPhase) throws -> Void

    init(directory: URL? = nil, service: String = Bundle.main.bundleIdentifier ?? "today.bsmart.ios",
         keychain: WalletKeychainAccess = SystemWalletKeychainAccess(), installationMarker: URL? = nil,
         clock: @escaping @Sendable () -> Date = { Date() },
         commitProbe: @escaping @Sendable (FundingJournalCommitPhase) throws -> Void = { _ in }) throws {
        files = FundingJournalFiles(directory: try directory ?? FundingJournalFiles.applicationDirectory())
        let marker = installationMarker ?? (directory == nil
            ? files.directory.deletingLastPathComponent().appendingPathComponent("FundingJournalInstallation.json") : nil)
        let anchorService: String
        if let marker {
            let files = files
            anchorService = try files.withLock {
                try FundingJournalInstallation.service(base: service, marker: marker, files: files)
            }
        } else {
            anchorService = service
        }
        anchors = .init(service: anchorService, keychain: keychain)
        self.clock = clock
        self.commitProbe = commitProbe
    }

    func records(wallet: DeviceWalletSummary) throws -> [FundingJournalRecord] {
        guard TradingWalletChallenge.validAddress(wallet.address) else { throw FundingJournalError.conflict }
        return try locked { _, _, records in
            records.sources.values.filter { $0.intent.accountID == wallet.accountID && $0.intent.owner == wallet.address }
                .sorted { $0.updatedAt == $1.updatedAt ? $0.intent.id.uuidString < $1.intent.id.uuidString : $0.updatedAt > $1.updatedAt }
        }
    }

    func consents(wallet: DeviceWalletSummary) throws -> [FundingConsentRecord] {
        guard TradingWalletChallenge.validAddress(wallet.address) else { throw FundingJournalError.conflict }
        return try locked { _, _, records in
            records.consents.values.filter { $0.plan.accountID == wallet.accountID && $0.plan.owner == wallet.address }
                .sorted { $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt }
        }
    }

    func history(wallet: DeviceWalletSummary) throws -> [FundingHistoryEntry] {
        guard TradingWalletChallenge.validAddress(wallet.address) else { throw FundingJournalError.conflict }
        return try locked { _, _, records in
            // Read both lifecycles under one lock; a linked authorization must not appear as a second deposit.
            let sources = try records.sources.values.filter {
                $0.intent.accountID == wallet.accountID && $0.intent.owner == wallet.address
            }.map { try FundingHistoryEntry(source: $0, observation: records.observations[$0.intent.id],
                                            attestation: records.attestations[$0.intent.id], forwarding: records.forwardings[$0.intent.id]) }
            let consents = try records.consents.values.filter {
                records.sources[$0.id] == nil && $0.plan.accountID == wallet.accountID && $0.plan.owner == wallet.address
            }.map(FundingHistoryEntry.init(consent:))
            return (sources + consents).sorted {
                $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt
            }
        }
    }

    func sourceLookup(id: UUID, wallet: DeviceWalletSummary) throws -> FundingSourceLookup {
        try locked { _, _, records in
            guard let record = records.sources[id], record.signed != nil, record.needsReconciliation else {
                throw FundingJournalError.invalidTransition
            }
            try record.intent.require(wallet: wallet)
            return FundingSourceLookup(record: record, previous: records.observations[id])
        }
    }

    func recordSourceObservation(_ observation: FundingSourceObservation, wallet: DeviceWalletSummary) throws {
        try locked(recordingEvidence: true) { anchor, database, records in
            guard let record = records.sources[observation.intentID] else { throw FundingJournalError.invalidTransition }
            try record.intent.require(wallet: wallet)
            if records.observations[observation.intentID] == observation { return }
            guard observation.observedAt <= clock(),
                  records.observations[observation.intentID]?.id == observation.previousID else { throw FundingJournalError.conflict }
            try appendEvent(.observation(observation), anchor: &anchor, database: database, records: &records)
        }
    }

    func attestationLookup(id: UUID, wallet: DeviceWalletSummary) throws -> CCTPAttestationLookup {
        try locked { _, _, records in
            guard let record = records.sources[id], let source = records.observations[id],
                  source.receipt?.succeeded == true else { throw FundingJournalError.invalidTransition }
            try record.intent.require(wallet: wallet)
            return .init(record: record, source: source, previous: records.attestations[id],
                         previousVerified: records.verifiedAttestations[id])
        }
    }

    func recordAttestation(_ observation: CCTPAttestationObservation, wallet: DeviceWalletSummary) throws {
        try locked(recordingEvidence: true) { anchor, database, records in
            guard let record = records.sources[observation.intentID] else { throw FundingJournalError.invalidTransition }
            try record.intent.require(wallet: wallet)
            if records.attestations[observation.intentID] == observation { return }
            guard observation.observedAt <= clock(),
                  records.observations[observation.intentID]?.id == observation.sourceObservationID,
                  records.attestations[observation.intentID]?.id == observation.previousID else { throw FundingJournalError.conflict }
            try appendEvent(.attestation(observation), anchor: &anchor, database: database, records: &records)
        }
    }

    func forwardingLookup(id: UUID, wallet: DeviceWalletSummary) throws -> CCTPForwardLookup {
        try locked { _, _, records in
            guard let record = records.sources[id], let source = records.observations[id],
                  let attestation = records.attestations[id], attestation.sourceObservationID == source.id,
                  attestation.proof != nil, attestation.forwardHash != nil else { throw FundingJournalError.invalidTransition }
            try record.intent.require(wallet: wallet)
            return .init(record: record, source: source, attestation: attestation, previous: records.forwardings[id])
        }
    }

    func recordForwarding(_ observation: CCTPForwardObservation, wallet: DeviceWalletSummary) throws {
        try locked(recordingEvidence: true) { anchor, database, records in
            guard let record = records.sources[observation.intentID] else { throw FundingJournalError.invalidTransition }
            try record.intent.require(wallet: wallet)
            if records.forwardings[observation.intentID] == observation { return }
            guard observation.observedAt <= clock(), records.observations[observation.intentID]?.id == observation.sourceObservationID,
                  records.attestations[observation.intentID]?.id == observation.attestationID,
                  records.forwardings[observation.intentID]?.id == observation.previousID else { throw FundingJournalError.conflict }
            try appendEvent(.forwarding(observation), anchor: &anchor, database: database, records: &records)
        }
    }

    func cancelReview(id: UUID, wallet: DeviceWalletSummary) throws {
        try locked { anchor, database, records in
            // Recheck the persisted state: a stale review screen cannot cancel an issued signing permit.
            if var record = records.sources[id] {
                try record.intent.require(wallet: wallet)
                if record.state == .cancelled { return }
                guard record.state == .prepared else { throw FundingJournalError.invalidTransition }
                record.state = .cancelled
                record.updatedAt = clock()
                try append(record, anchor: &anchor, database: database, records: &records)
            } else if var record = records.consents[id] {
                try record.plan.require(wallet: wallet)
                if record.state == .cancelled { return }
                guard record.state == .review else { throw FundingJournalError.invalidTransition }
                record.state = .cancelled
                record.updatedAt = clock()
                try appendEvent(.consent(record), anchor: &anchor, database: database, records: &records)
            } else { throw FundingJournalError.invalidTransition }
        }
    }

    func beginConsent(id: UUID, plan: CCTPDepositPlan, wallet: DeviceWalletSummary) throws -> FundingConsentRecord {
        try locked { anchor, database, records in
            try plan.validate(wallet: wallet, now: clock())
            let fixed = try FundingConsentPlan(plan)
            if let previous = records.consents[id] {
                guard previous.plan == fixed else { throw FundingJournalError.conflict }
                return previous
            }
            let record = FundingConsentRecord(id: id, plan: fixed, state: .review, signature: nil, updatedAt: clock())
            try appendEvent(.consent(record), anchor: &anchor, database: database, records: &records)
            return record
        }
    }

    func beginAuthorization(id: UUID, wallet: DeviceWalletSummary) throws -> FundingAuthorizationPermit {
        try locked { anchor, database, records in
            guard var record = records.consents[id], record.state == .review else { throw FundingJournalError.invalidTransition }
            try record.plan.require(wallet: wallet, now: clock())
            record.state = .authorizing
            record.updatedAt = clock()
            try appendEvent(.consent(record), anchor: &anchor, database: database, records: &records)
            try record.plan.require(wallet: wallet, now: clock())
            return try FundingAuthorizationPermit(record)
        }
    }

    func recordAuthorization(id: UUID, signature: String, wallet: DeviceWalletSummary) throws -> FundingConsentRecord {
        try locked(recordingEvidence: true) { anchor, database, records in
            guard var record = records.consents[id] else { throw FundingJournalError.invalidTransition }
            try record.plan.require(wallet: wallet)
            if let previous = record.signature {
                guard previous == signature else { throw FundingJournalError.conflict }
                return record
            }
            guard record.state == .authorizing else { throw FundingJournalError.invalidTransition }
            record.state = .authorized
            record.signature = signature
            record.updatedAt = clock()
            try appendEvent(.consent(record), anchor: &anchor, database: database, records: &records)
            return record
        }
    }

    func cancelConsent(id: UUID, wallet: DeviceWalletSummary) throws -> FundingConsentRecord {
        try locked { anchor, database, records in
            guard var record = records.consents[id] else { throw FundingJournalError.invalidTransition }
            try record.plan.require(wallet: wallet)
            if record.state == .cancelled { return record }
            guard record.state == .review else { throw FundingJournalError.invalidTransition }
            record.state = .cancelled
            record.updatedAt = clock()
            try appendEvent(.consent(record), anchor: &anchor, database: database, records: &records)
            return record
        }
    }

    func reserve(id: UUID, transaction: CCTPSourceTransaction, wallet: DeviceWalletSummary) throws -> FundingJournalRecord {
        let now = clock()
        try validate(transaction, wallet: wallet, now: now)
        let intent = FundingJournalIntent(id: id, transaction: transaction)
        return try locked { anchor, database, records in
            if let existing = records.sources[id] {
                guard existing.intent == intent else { throw FundingJournalError.conflict }
                return existing
            }
            let record = FundingJournalRecord(intent: intent, state: .prepared, signed: nil, updatedAt: now)
            try append(record, anchor: &anchor, database: database, records: &records)
            return record
        }
    }

    func beginSigning(id: UUID, transaction: CCTPSourceTransaction, wallet: DeviceWalletSummary) throws -> FundingSigningPermit {
        try validate(transaction, wallet: wallet, now: clock())
        return try locked { anchor, database, records in
            var record = try matching(id, transaction: transaction, wallet: wallet, records: records)
            guard record.state == .prepared else { throw FundingJournalError.invalidTransition }
            record.state = .signing
            record.updatedAt = clock()
            try append(record, anchor: &anchor, database: database, records: &records)
            try record.intent.require(wallet: wallet, now: clock())
            return FundingSigningPermit(record.intent, consent: records.consents[id])
        }
    }

    func acceptSignature(id: UUID, signed: CCTPSignedSourceTransaction, wallet: DeviceWalletSummary) throws -> FundingJournalRecord {
        return try locked(recordingEvidence: true) { anchor, database, records in
            guard let record = records.sources[id], record.intent == FundingJournalIntent(id: id, transaction: signed.transaction) else {
                throw FundingJournalError.conflict
            }
            try record.intent.require(wallet: wallet)
            let signature = FundingJournalRecord.Signed(signature: signed.signature, raw: signed.raw, hash: signed.hash)
            return try persist(signature, record: record, anchor: &anchor, database: database, records: &records)
        }
    }

    func recordSignature(id: UUID, signature: Data, wallet: DeviceWalletSummary) throws -> FundingJournalRecord {
        try locked(recordingEvidence: true) { anchor, database, records in
            guard let record = records.sources[id] else { throw FundingJournalError.invalidTransition }
            try record.intent.require(wallet: wallet)
            // Preserve an already-created signature even after expiry. This never authorizes submission.
            let archived = try CCTPSourceTransaction.archiveSignature(intent: record.intent, signature: signature)
            return try persist(archived, record: record, anchor: &anchor, database: database, records: &records)
        }
    }

    func beginSubmission(id: UUID, signed: CCTPSignedSourceTransaction, wallet: DeviceWalletSummary,
                         check: FundingSubmissionCheck) throws -> FundingSubmissionPermit {
        try validate(signed.transaction, wallet: wallet, now: clock())
        try check.validate(hash: signed.hash, wallet: wallet, now: clock())
        return try locked { anchor, database, records in
            var record = try matching(id, transaction: signed.transaction, wallet: wallet, records: records)
            guard record.state == .signed, records.observations[id] == nil, let stored = record.signed,
                  stored.raw == signed.raw, stored.hash == signed.hash, stored.signature == signed.signature else {
                throw FundingJournalError.invalidTransition
            }
            record.state = .submitting
            record.updatedAt = clock()
            // Do not return bytes for submission until both the database and anchor are committed.
            try append(record, anchor: &anchor, database: database, records: &records)
            try record.intent.require(wallet: wallet, now: clock())
            try check.validate(hash: signed.hash, wallet: wallet, now: clock())
            return FundingSubmissionPermit(record, signed: stored, check: check, wallet: wallet,
                                           consent: records.consents[id], clock: clock)
        }
    }

    func recordSubmissionResult(id: UUID, wallet: DeviceWalletSummary, reportedHash: String?) throws -> FundingJournalRecord {
        try locked(recordingEvidence: true) { anchor, database, records in
            guard var record = records.sources[id], let signed = record.signed else { throw FundingJournalError.invalidTransition }
            try record.intent.require(wallet: wallet)
            guard [.submitting, .submitted, .uncertain].contains(record.state) else { throw FundingJournalError.invalidTransition }
            let next: FundingJournalRecord.State = reportedHash == signed.hash ? .submitted : .uncertain
            if record.state == next { return record }
            record.state = next
            record.updatedAt = clock()
            try append(record, anchor: &anchor, database: database, records: &records)
            return record
        }
    }

    func cancelPrepared(id: UUID, wallet: DeviceWalletSummary) throws -> FundingJournalRecord {
        try locked { anchor, database, records in
            guard var record = records.sources[id] else { throw FundingJournalError.invalidTransition }
            try record.intent.require(wallet: wallet)
            if record.state == .cancelled { return record }
            guard record.state == .prepared else { throw FundingJournalError.invalidTransition }
            record.state = .cancelled
            record.updatedAt = clock()
            try append(record, anchor: &anchor, database: database, records: &records)
            return record
        }
    }

    private func matching(_ id: UUID, transaction: CCTPSourceTransaction, wallet: DeviceWalletSummary,
                          records: FundingJournalSnapshot) throws -> FundingJournalRecord {
        guard let record = records.sources[id], record.intent == FundingJournalIntent(id: id, transaction: transaction) else {
            throw FundingJournalError.conflict
        }
        try record.intent.require(wallet: wallet, now: clock())
        return record
    }

    private func persist(_ signature: FundingJournalRecord.Signed, record: FundingJournalRecord,
                         anchor: inout FundingJournalAnchor, database: FundingJournalDatabase,
                         records: inout FundingJournalSnapshot) throws -> FundingJournalRecord {
        if let existing = record.signed {
            guard existing == signature else { throw FundingJournalError.conflict }
            return record
        }
        guard record.state == .signing else { throw FundingJournalError.invalidTransition }
        var next = record
        next.state = .signed
        next.signed = signature
        next.updatedAt = clock()
        try append(next, anchor: &anchor, database: database, records: &records)
        return next
    }

    private func validate(_ transaction: CCTPSourceTransaction, wallet: DeviceWalletSummary, now: Date) throws {
        guard transaction.preflight.plan.accountID == wallet.accountID, transaction.preflight.plan.owner == wallet.address else {
            throw FundingJournalError.conflict
        }
        guard wallet.canAuthorizeTransactions else { throw FundingJournalError.invalidTransition }
        do { try transaction.preflight.validate(wallet: wallet, now: now) }
        catch CCTPFundingError.expiredQuote { throw FundingJournalError.expired }
        catch FundingPreflightError.staleState { throw FundingJournalError.expired }
        catch { throw FundingJournalError.integrity }
    }

    func locked<T>(recordingEvidence: Bool = false,
                           _ operation: (inout FundingJournalAnchor, FundingJournalDatabase,
                                        inout FundingJournalSnapshot) throws -> T) throws -> T {
        if !recordingEvidence { try Task.checkCancellation() }
        do {
            return try withVerifiedLedger(recordingEvidence: recordingEvidence, operation)
        } catch let error as FundingJournalError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch {
            // Codec/preflight wording like "no transfer was made" is unsafe once signing has started.
            throw FundingJournalError.unavailable
        }
    }

    private func withVerifiedLedger<T>(recordingEvidence: Bool,
                                      _ operation: (inout FundingJournalAnchor, FundingJournalDatabase,
                                                    inout FundingJournalSnapshot) throws -> T) throws -> T {
        try files.withLock {
            let exists = try files.databaseExists()
            var anchor: FundingJournalAnchor
            if let stored = try anchors.load() { anchor = stored }
            else {
                guard !exists else { throw FundingJournalError.integrity }
                anchor = .create()
                try anchors.insert(anchor)
            }
            let mayInitialize = anchor.committed == .empty && anchor.pending == nil
            guard exists || mayInitialize else { throw FundingJournalError.integrity }
            let database = try FundingJournalDatabase(url: files.database, mayInitialize: mayInitialize)
            try files.protect(files.database, directory: false)
            let (head, replayed) = try database.replay(anchor: anchor)
            var records = replayed
            if let pending = anchor.pending {
                if head == pending { anchor.committed = pending }
                else if head != anchor.committed { throw FundingJournalError.integrity }
                anchor.pending = nil
                try anchors.save(anchor)
            } else if head != anchor.committed { throw FundingJournalError.integrity }
            if !recordingEvidence { try Task.checkCancellation() }
            let result = try operation(&anchor, database, &records)
            if !recordingEvidence { try Task.checkCancellation() }
            return result
        }
    }

    private func append(_ record: FundingJournalRecord, anchor: inout FundingJournalAnchor,
                        database: FundingJournalDatabase, records: inout FundingJournalSnapshot) throws {
        try appendEvent(.source(record), anchor: &anchor, database: database, records: &records)
    }

    func appendEvent(_ event: FundingJournalEvent, anchor: inout FundingJournalAnchor,
                             database: FundingJournalDatabase, records: inout FundingJournalSnapshot) throws {
        var next = records
        try next.apply(event)
        guard anchor.committed.sequence < FundingJournalDatabase.maximumEvents else { throw FundingJournalError.capacity }
        let (sealed, pending) = try FundingJournalCryptography.sealEvent(event, anchor: anchor)
        anchor.pending = pending
        try anchors.save(anchor)
        try commitProbe(.afterPendingAnchor)
        try database.execute("BEGIN IMMEDIATE")
        do {
            try database.append(sealed, checkpoint: pending)
            try commitProbe(.beforeCommit)
            try database.execute("COMMIT")
        } catch { try? database.execute("ROLLBACK"); throw error }
        try commitProbe(.afterCommit)
        anchor.committed = pending
        anchor.pending = nil
        try anchors.save(anchor)
        records = next
    }
}
