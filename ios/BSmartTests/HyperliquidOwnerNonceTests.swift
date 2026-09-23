import XCTest
@testable import BSmart

final class HyperliquidOwnerNonceTests: XCTestCase {
    typealias F = HyperliquidTradingFixture

    func testPendingOrderBlocksWithdrawalAcrossJournalInstances() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (journal, _, _) = try await context.base.submitting()
        let second = try context.base.journal()
        await expectJournalFailure { try await second.reserveWithdrawal(id: UUID(), intent: context.intent(), wallet: F.wallet) }
        let orders = try await journal.orderRecords(wallet: F.wallet)
        XCTAssertEqual(orders.count, 1)
    }

    func testPendingWithdrawalBlocksOrderEvenUnderDifferentAccountID() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (journal, _, id) = try await context.submitting()
        _ = try await journal.recordWithdrawalResponse(id: id, response: nil, wallet: F.wallet)
        let quote = try await context.base.preview()
        await expectJournalFailure {
            try await context.base.journal().reserveOrder(id: UUID(), preview: quote, wallet: F.wallet,
                                                        continuousNow: context.base.clock.instant)
        }
        let other = DeviceWalletSummary(accountID: UUID(), address: F.wallet.address, recoveryVerified: true)
        let nonce = try await journal.nextHyperliquidNonce(wallet: other)
        await expectJournalFailure { try await journal.reserveWithdrawal(id: UUID(), intent: context.intent(nonce: nonce, wallet: other), wallet: other) }
    }

    func testNonceHintReflectsOldOrderJournalAfterRestart() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (journal, quote, id) = try await context.submitting()
        _ = try await journal.recordOrderResponse(id: id, response: WithdrawalJournalContext.rejected, wallet: F.wallet)
        let restored = try context.journal()
        let nonce = try await restored.nextHyperliquidNonce(wallet: F.wallet)
        XCTAssertGreaterThan(nonce, quote.order.nonce)
        let intent = try HyperliquidWithdrawalIntent(wallet: F.wallet, recipient: "0x2222222222222222222222222222222222222222",
                                                     amount: "10", source: .perps, nonce: nonce)
        _ = try await restored.reserveWithdrawal(id: UUID(), intent: intent, wallet: F.wallet)
        let next = try await restored.nextOrderNonce(wallet: F.wallet)
        XCTAssertEqual(next, nonce + 1)
        let history = try await restored.orderRecords(wallet: F.wallet)
        XCTAssertEqual(history.first?.state, .rejected)
    }

    func testExpiredReviewCannotPermitLowerOrderNonceOrReusedID() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (journal, intent, id) = try await context.review()
        _ = try await journal.cancelWithdrawalReview(id: id, wallet: F.wallet)
        let quote = try await context.base.preview()
        await expectJournalFailure {
            try await journal.reserveOrder(id: UUID(), preview: quote, wallet: F.wallet, continuousNow: context.base.clock.instant)
        }
        await expectJournalFailure { try await journal.reserveWithdrawal(id: id, intent: context.intent(nonce: intent.nonce + 1), wallet: F.wallet) }
    }

    func testIndependentWalletDoesNotShareNonceHighWaterMark() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (journal, original, _) = try await context.review()
        let other = DeviceWalletSummary(accountID: UUID(), address: "0x4444444444444444444444444444444444444444", recoveryVerified: true)
        let nonce = try await journal.nextHyperliquidNonce(wallet: other)
        XCTAssertEqual(nonce, original.nonce)
        _ = try await journal.reserveWithdrawal(id: UUID(), intent: context.intent(nonce: nonce, wallet: other), wallet: other)
        let first = try await journal.withdrawalRecords(wallet: F.wallet)
        let second = try await journal.withdrawalRecords(wallet: other)
        XCTAssertEqual(first.count, 1); XCTAssertEqual(second.count, 1)
    }

    func testConcurrentReservationsForOneOwnerHaveOneWinner() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let first = try context.base.journal(), second = try context.base.journal(), intent = try context.intent()
        let winners = await withTaskGroup(of: Bool.self) { group in
            for journal in [first, second] {
                group.addTask {
                    do { _ = try await journal.reserveWithdrawal(id: UUID(), intent: intent, wallet: F.wallet); return true }
                    catch { return false }
                }
            }
            var count = 0
            for await won in group { if won { count += 1 } }
            return count
        }
        XCTAssertEqual(winners, 1)
        let records = try await context.base.journal().withdrawalRecords(wallet: F.wallet)
        XCTAssertEqual(records.count, 1)
    }

    func testClockRollbackCannotCreateOldNonce() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (journal, _, _) = try await context.review()
        context.base.clock.advance(wall: -5)
        await expectJournalFailure { try await journal.nextHyperliquidNonce(wallet: F.wallet) }
    }

    func testSupersededReviewCannotReviveWhenClockMovesBack() async throws {
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (journal, original, id) = try await context.review()
        context.base.clock.advance(wall: 61, steady: .seconds(61))
        _ = try await journal.reserveWithdrawal(id: UUID(), intent: context.intent(), wallet: F.wallet)
        context.base.clock.advance(wall: -60)
        await expectJournalFailure { try await journal.recordWithdrawalSigningStarted(id: id, intent: original, wallet: F.wallet) }
        let history = try await journal.withdrawalRecords(wallet: F.wallet)
        XCTAssertEqual(history.first(where: { $0.id == id })?.state, .review)
    }

    func testOrderCanFollowCancelledWithdrawalUsingFreshSharedNonce() async throws {
        typealias Q = HyperliquidQuoteFixture
        let context = WithdrawalJournalContext(); defer { context.base.cleanup() }
        let (journal, withdrawal, id) = try await context.review()
        _ = try await journal.cancelWithdrawalReview(id: id, wallet: F.wallet)
        let nonce = try await journal.nextOrderNonce(wallet: F.wallet)
        XCTAssertGreaterThan(nonce, withdrawal.nonce)
        let order = try HyperliquidOrderIntent(wallet: F.wallet, market: Q.market(), side: .buy, size: "1", limitPrice: "221",
            reduceOnly: false, cloid: "0x00000000000000000000000000000023", nonce: nonce, expiresAfter: nonce + 30_000)
        let quote = try await HyperliquidOrderPreviewProvider(reader: TradingCheckReaderStub(preview: [Q.fees(), Q.book()]),
            clock: { context.base.clock.now }, continuousClock: { context.base.clock.instant }).preview(order: order,
                wallet: F.wallet, account: Q.snapshot(clock: context.base.clock), reviewedLeverage: 10, reviewedMarginMode: .cross)
        let reserved = try await journal.reserveOrder(id: UUID(), preview: quote, wallet: F.wallet,
                                                      continuousNow: context.base.clock.instant)
        let orders = try await context.base.journal().orderRecords(wallet: F.wallet)
        XCTAssertEqual(orders.first, reserved)
        XCTAssertEqual(reserved.order.nonce, nonce)
    }
}
