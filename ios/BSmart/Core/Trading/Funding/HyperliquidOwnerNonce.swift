import Foundation

extension FundingJournalSnapshot {
    func latestHyperliquidNonce(owner: String) -> UInt64 {
        max(orders.values.filter { $0.order.owner == owner }.map(\.order.nonce).max() ?? 0,
            withdrawals.values.filter { $0.intent.owner == owner }.map(\.intent.nonce).max() ?? 0,
            accountSetups.values.filter { $0.owner == owner }.map(\.nonce).max() ?? 0,
            leverages.values.filter { $0.owner == owner }.map(\.nonce).max() ?? 0)
    }

    func checkHyperliquidReservation(id: UUID, owner: String, nonce: UInt64, at now: Date) throws {
        guard orders[id] == nil, withdrawals[id] == nil, accountSetups[id] == nil, leverages[id] == nil,
              nonce > latestHyperliquidNonce(owner: owner),
              !orders.values.contains(where: { $0.order.owner == owner && $0.blocksNewOrder(at: now) }),
              !withdrawals.values.contains(where: { $0.intent.owner == owner && $0.blocksNewAction(at: now) }) else {
            throw FundingJournalError.conflict
        }
    }
}

extension FundingTransactionJournal {
    // This is not a reservation: the durable insert rechecks uniqueness under the file lock.
    func nextHyperliquidNonce(wallet: DeviceWalletSummary) throws -> UInt64 {
        guard TradingWalletChallenge.validAddress(wallet.address), wallet.address == wallet.address.lowercased(),
              wallet.address != "0x" + String(repeating: "0", count: 40) else { throw FundingJournalError.conflict }
        return try locked { _, _, snapshot in
            let ms = clock().timeIntervalSince1970 * 1000
            guard ms.isFinite, ms > 0, ms < 9_007_199_254_680_991 else { throw FundingJournalError.expired }
            let latest = snapshot.latestHyperliquidNonce(owner: wallet.address)
            guard latest < UInt64(ms) + 1000 else { throw FundingJournalError.conflict }
            return max(UInt64(ms), latest + 1)
        }
    }
}
