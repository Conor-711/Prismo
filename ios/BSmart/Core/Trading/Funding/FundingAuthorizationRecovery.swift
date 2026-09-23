import Foundation

extension FundingTransactionJournal {
    // beginSubmission commits .submitting BEFORE issuing the sole broadcast capability.
    // A .signed record never reached that boundary. Retain its bytes, but permanently revoke submission.
    func finishUnsubmittedSource(id: UUID, wallet: DeviceWalletSummary) throws -> Bool {
        try locked { anchor, database, records in
            guard var source = records.sources[id] else { return false }
            try source.intent.require(wallet: wallet)
            guard source.canFinishWithoutSubmission(observation: records.observations[id]) else { return false }
            if source.state == .notSubmitted { return true }
            source.state = .notSubmitted
            source.updatedAt = max(clock(), source.updatedAt)
            try appendEvent(.source(source), anchor: &anchor, database: database, records: &records)
            return true
        }
    }

    // The fixed extension requires msg.sender == owner. Its USDC authorization alone cannot send funds.
    // Never release an in-flight signer or any source transaction; their outcome may be unknown.
    func finishUnsubmittedAuthorization(id: UUID, wallet: DeviceWalletSummary) throws -> Bool {
        try locked { anchor, database, records in
            guard var consent = records.consents[id], records.sources[id] == nil else { return false }
            try consent.plan.require(wallet: wallet)
            if consent.state == .notSubmitted { return true }
            guard consent.state == .authorized else { return false }
            consent.state = .notSubmitted
            consent.updatedAt = max(clock(), consent.updatedAt)
            try appendEvent(.consent(consent), anchor: &anchor, database: database, records: &records)
            return true
        }
    }

    // Only orphaned authorizations can expire here. Signed/source transactions are never deleted or retried.
    func expireAuthorizations(wallet: DeviceWalletSummary, source: ArbitrumWalletSnapshot) throws {
        try source.validate(wallet: wallet, now: clock())
        try locked { anchor, database, records in
            let candidates = records.consents.values.filter {
                $0.plan.accountID == wallet.accountID && $0.plan.owner == wallet.address
                    && $0.reservesOwner && records.sources[$0.id] == nil
            }
            for var consent in candidates {
                let plan = try consent.plan.restored()
                guard source.block.timestamp.timeIntervalSince1970 > Double(plan.validBefore) else { continue }
                consent.state = .expired
                consent.expiredAtSourceTime = source.block.timestamp
                consent.updatedAt = clock()
                try appendEvent(.consent(consent), anchor: &anchor, database: database, records: &records)
            }
        }
    }
}
