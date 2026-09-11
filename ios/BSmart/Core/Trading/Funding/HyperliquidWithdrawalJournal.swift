import Foundation

// Records lifecycle evidence only. No method here grants device-key or network access.
extension FundingTransactionJournal {
    func withdrawalRecords(wallet: DeviceWalletSummary) throws -> [HyperliquidWithdrawalRecord] {
        try locked { _, _, snapshot in
            snapshot.withdrawals.values.filter { $0.intent.accountID == wallet.accountID && $0.intent.owner == wallet.address }
                .sorted { $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt }
        }
    }

    func reserveWithdrawal(id: UUID, intent: HyperliquidWithdrawalIntent, wallet: DeviceWalletSummary) throws -> HyperliquidWithdrawalRecord {
        try intent.validate(wallet: wallet)
        return try locked { anchor, database, snapshot in
            let now = clock()
            try snapshot.checkHyperliquidReservation(id: id, owner: intent.owner, nonce: intent.nonce, at: now)
            let record = HyperliquidWithdrawalRecord(id: id, intent: .init(intent), createdAt: now,
                reviewExpiresAt: now.addingTimeInterval(60), state: .review, signature: nil, response: nil, updatedAt: now)
            try appendEvent(.withdrawal(record), anchor: &anchor, database: database, records: &snapshot)
            return record
        }
    }

    func cancelWithdrawalReview(id: UUID, wallet: DeviceWalletSummary) throws -> HyperliquidWithdrawalRecord {
        try locked { anchor, database, snapshot in
            guard var record = snapshot.withdrawals[id] else { throw FundingJournalError.invalidTransition }
            _ = try record.intent.restored(wallet: wallet)
            if record.state == .cancelled { return record }
            guard record.state == .review else { throw FundingJournalError.invalidTransition }
            record.state = .cancelled; record.updatedAt = clock()
            try appendEvent(.withdrawal(record), anchor: &anchor, database: database, records: &snapshot)
            return record
        }
    }

    // Persist before any future signer access. A return value is not a signing permit.
    func recordWithdrawalSigningStarted(id: UUID, intent: HyperliquidWithdrawalIntent,
                                        wallet: DeviceWalletSummary) throws -> HyperliquidWithdrawalRecord {
        try locked { anchor, database, snapshot in
            guard var record = snapshot.withdrawals[id], record.state == .review,
                  try record.intent.restored(wallet: wallet) == intent else { throw FundingJournalError.conflict }
            record.state = .signing; record.updatedAt = clock()
            try appendEvent(.withdrawal(record), anchor: &anchor, database: database, records: &snapshot)
            return record
        }
    }

    func recordWithdrawalSignature(id: UUID, signature: String, wallet: DeviceWalletSummary) throws -> HyperliquidWithdrawalRecord {
        try locked(recordingEvidence: true) { anchor, database, snapshot in
            guard var record = snapshot.withdrawals[id], record.state == .signing else { throw FundingJournalError.invalidTransition }
            _ = try record.intent.restored(wallet: wallet)
            record.signature = signature; record.state = .signed
            record.updatedAt = try withdrawalEvidenceTime(after: record.updatedAt)
            try appendEvent(.withdrawal(record), anchor: &anchor, database: database, records: &snapshot)
            return record
        }
    }

    // Future transport must persist this phase before starting its one-shot request.
    func recordWithdrawalSubmissionStarted(id: UUID, intent: HyperliquidWithdrawalIntent,
                                           wallet: DeviceWalletSummary) throws -> HyperliquidWithdrawalRecord {
        try locked { anchor, database, snapshot in
            guard var record = snapshot.withdrawals[id], record.state == .signed,
                  try record.intent.restored(wallet: wallet) == intent else { throw FundingJournalError.conflict }
            record.state = .submitting; record.updatedAt = clock()
            try appendEvent(.withdrawal(record), anchor: &anchor, database: database, records: &snapshot)
            return record
        }
    }

    func recordWithdrawalResponse(id: UUID, response: Data?, wallet: DeviceWalletSummary) throws -> HyperliquidWithdrawalRecord {
        try locked(recordingEvidence: true) { anchor, database, snapshot in
            guard var record = snapshot.withdrawals[id], record.state == .submitting else { throw FundingJournalError.invalidTransition }
            _ = try record.intent.restored(wallet: wallet)
            record.state = .uncertain; record.response = nil
            record.updatedAt = try withdrawalEvidenceTime(after: record.updatedAt)
            if let response, let ack = try? HyperliquidWithdrawalAcknowledgement.decode(response) {
                record.response = response
                switch ack { case .accepted: record.state = .accepted; case .rejected: record.state = .rejected }
            }
            try appendEvent(.withdrawal(record), anchor: &anchor, database: database, records: &snapshot)
            return record
        }
    }

    private func withdrawalEvidenceTime(after previous: Date) throws -> Date {
        let now = clock()
        guard now.timeIntervalSince1970.isFinite else { throw FundingJournalError.unavailable }
        // The journal sequence orders evidence; a clock correction cannot discard a returned signature/response.
        return max(now, previous)
    }
}
