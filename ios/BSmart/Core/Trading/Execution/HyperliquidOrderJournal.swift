import Foundation

final class HyperliquidOrderSigningPermit: @unchecked Sendable {
    let id: UUID
    let preview: HyperliquidOrderPreview
    private let lock = NSLock()
    private var consumed = false
    fileprivate init(id: UUID, preview: HyperliquidOrderPreview) { self.id = id; self.preview = preview }

    func consume(wallet: DeviceWalletSummary, now: Date, continuousNow: ContinuousClock.Instant = .now) throws {
        lock.lock(); defer { lock.unlock() }
        guard !consumed else { throw FundingJournalError.invalidTransition }
        consumed = true
        try preview.validate(wallet: wallet, now: now, continuousNow: continuousNow)
    }
}

final class HyperliquidOrderSubmissionPermit: @unchecked Sendable {
    let id: UUID
    let order: HyperliquidOrderIntent
    private let body: Data
    private let preview: HyperliquidOrderPreview
    private let wallet: DeviceWalletSummary
    private let clock: @Sendable () -> Date
    private let continuousClock: @Sendable () -> ContinuousClock.Instant
    private let lock = NSLock()
    private var consumed = false

    fileprivate init(id: UUID, preview: HyperliquidOrderPreview, body: Data, wallet: DeviceWalletSummary,
                     clock: @escaping @Sendable () -> Date, continuousClock: @escaping @Sendable () -> ContinuousClock.Instant) {
        self.id = id; order = preview.order; self.preview = preview; self.body = body; self.wallet = wallet
        self.clock = clock; self.continuousClock = continuousClock
    }

    func start<T>(lease: FundingSigningLease, _ operation: (Data) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard !consumed else { throw FundingJournalError.invalidTransition }
        consumed = true
        return try lease.perform(wallet: wallet) {
            try preview.validate(wallet: wallet, now: clock(), continuousNow: continuousClock())
            return try operation(body)
        }
    }
}

extension FundingTransactionJournal {
    func reconcileOrder(id: UUID, response: Data, wallet: DeviceWalletSummary) throws -> HyperliquidOrderRecord {
        try locked(recordingEvidence: true) { anchor, database, snapshot in
            guard var record = snapshot.orders[id], [.submitting, .uncertain].contains(record.state) else {
                throw FundingJournalError.invalidTransition
            }
            _ = try HyperliquidOrderStatus.decode(response, order: record.order.restored(wallet: wallet))
            record.state = .reconciled; record.reconciliation = response; record.updatedAt = max(clock(), record.updatedAt)
            try appendEvent(.order(record), anchor: &anchor, database: database, records: &snapshot)
            return record
        }
    }

    func orderRecords(wallet: DeviceWalletSummary) throws -> [HyperliquidOrderRecord] {
        try locked { _, _, snapshot in
            snapshot.orders.values.filter { $0.order.owner == wallet.address && $0.order.accountID == wallet.accountID }
                .sorted { $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt }
        }
    }

    func nextOrderNonce(wallet: DeviceWalletSummary) throws -> UInt64 {
        try nextHyperliquidNonce(wallet: wallet)
    }

    func reserveOrder(id: UUID, preview: HyperliquidOrderPreview, wallet: DeviceWalletSummary,
                      continuousNow: ContinuousClock.Instant = .now) throws -> HyperliquidOrderRecord {
        try preview.validate(wallet: wallet, now: clock(), continuousNow: continuousNow)
        let archived = try HyperliquidArchivedOrder(preview.order)
        return try locked { anchor, database, snapshot in
            try snapshot.checkHyperliquidReservation(id: id, owner: wallet.address, nonce: archived.nonce, at: clock())
            let previous = snapshot.orders.values.filter { $0.order.owner == wallet.address }
            guard !previous.contains(where: { $0.order.cloid == archived.cloid }) else {
                throw FundingJournalError.conflict
            }
            let record = HyperliquidOrderRecord(id: id, order: archived, leverage: preview.reviewedLeverage,
                marginMode: preview.reviewedMarginMode, state: .review, signature: nil, response: nil, updatedAt: clock())
            try appendEvent(.order(record), anchor: &anchor, database: database, records: &snapshot)
            return record
        }
    }

    func beginOrderSigning(id: UUID, preview: HyperliquidOrderPreview, wallet: DeviceWalletSummary,
                           continuousNow: ContinuousClock.Instant = .now) throws -> HyperliquidOrderSigningPermit {
        try preview.validate(wallet: wallet, now: clock(), continuousNow: continuousNow)
        return try locked { anchor, database, snapshot in
            guard var record = snapshot.orders[id], record.state == .review,
                  try record.order.restored(wallet: wallet) == preview.order,
                  record.leverage == preview.reviewedLeverage, record.marginMode == preview.reviewedMarginMode else {
                throw FundingJournalError.conflict
            }
            record.state = .signing; record.updatedAt = clock()
            try appendEvent(.order(record), anchor: &anchor, database: database, records: &snapshot)
            return .init(id: id, preview: preview)
        }
    }

    func recordOrderSignature(id: UUID, signature: String, wallet: DeviceWalletSummary) throws -> HyperliquidOrderRecord {
        try locked(recordingEvidence: true) { anchor, database, snapshot in
            guard var record = snapshot.orders[id], record.state == .signing else { throw FundingJournalError.invalidTransition }
            _ = try record.order.restored(wallet: wallet)
            record.signature = signature; record.state = .signed; record.updatedAt = clock()
            try appendEvent(.order(record), anchor: &anchor, database: database, records: &snapshot)
            return record
        }
    }

    func beginOrderSubmission(id: UUID, preview: HyperliquidOrderPreview, wallet: DeviceWalletSummary,
                              continuousClock: @escaping @Sendable () -> ContinuousClock.Instant = { .now }) throws -> HyperliquidOrderSubmissionPermit {
        try preview.validate(wallet: wallet, now: clock(), continuousNow: continuousClock())
        return try locked { anchor, database, snapshot in
            guard var record = snapshot.orders[id], record.state == .signed, let signature = record.signature,
                  try record.order.restored(wallet: wallet) == preview.order,
                  record.leverage == preview.reviewedLeverage, record.marginMode == preview.reviewedMarginMode else {
                throw FundingJournalError.conflict
            }
            let body = try HyperliquidOrderCodec.envelope(preview.order, signature: signature)
            record.state = .submitting; record.updatedAt = clock()
            try appendEvent(.order(record), anchor: &anchor, database: database, records: &snapshot)
            return .init(id: id, preview: preview, body: body, wallet: wallet, clock: clock, continuousClock: continuousClock)
        }
    }

    func recordOrderResponse(id: UUID, response: Data?, wallet: DeviceWalletSummary) throws -> HyperliquidOrderRecord {
        try locked(recordingEvidence: true) { anchor, database, snapshot in
            guard var record = snapshot.orders[id], record.state == .submitting else { throw FundingJournalError.invalidTransition }
            let intent = try record.order.restored(wallet: wallet)
            record.state = .uncertain; record.response = nil; record.updatedAt = clock()
            if let response, response.count <= 8192, let ack = try? HyperliquidOrderAcknowledgement.decode(response, for: intent) {
                record.response = response
                switch ack { case .filled: record.state = .filled; case .rejected: record.state = .rejected }
            }
            try appendEvent(.order(record), anchor: &anchor, database: database, records: &snapshot)
            return record
        }
    }
}
