import Foundation

struct HyperliquidOrderFillBatch: Codable {
    let orderRecordID: UUID
    let fills: [HyperliquidOrderFill]
}

extension FundingJournalSnapshot {
    mutating func applyOrderFills(_ batch: HyperliquidOrderFillBatch) throws {
        guard let record = orders[batch.orderRecordID], [.filled, .reconciled].contains(record.state),
              (1...8).contains(batch.fills.count) else { throw FundingJournalError.invalidTransition }
        let existing = orderFills[record.id] ?? [:]
        let summary = try HyperliquidFillSummary(record: record, fills: Array(existing.values) + batch.fills)
        orderFills[record.id] = Dictionary(uniqueKeysWithValues: summary.fills.map { ($0.tid, $0) })
    }
}

extension FundingTransactionJournal {
    func orderFillSummaries(wallet: DeviceWalletSummary) throws -> [UUID: HyperliquidFillSummary] {
        try locked { _, _, snapshot in
            var values: [UUID: HyperliquidFillSummary] = [:]
            for record in snapshot.orders.values where record.order.owner == wallet.address && record.order.accountID == wallet.accountID {
                if record.fillOrderID != nil {
                    values[record.id] = try .init(record: record, fills: Array((snapshot.orderFills[record.id] ?? [:]).values))
                }
            }
            return values
        }
    }

    func recordOrderFills(id: UUID, response: Data, wallet: DeviceWalletSummary) throws {
        try locked(recordingEvidence: true) { anchor, database, snapshot in
            guard let record = snapshot.orders[id] else { throw FundingJournalError.invalidTransition }
            _ = try record.order.restored(wallet: wallet)
            let incoming = try HyperliquidOrderFill.decode(response, record: record)
            let previous = snapshot.orderFills[id] ?? [:]
            // Validate the whole observation before committing any new rows; repeats are no-ops.
            let summary = try HyperliquidFillSummary(record: record, fills: Array(previous.values) + incoming)
            let added = summary.fills.filter { previous[$0.tid] == nil }
            for start in stride(from: 0, to: added.count, by: 8) {
                let batch = HyperliquidOrderFillBatch(orderRecordID: id, fills: Array(added[start..<min(start + 8, added.count)]))
                try appendEvent(.orderFills(batch), anchor: &anchor, database: database, records: &snapshot)
            }
        }
    }
}
