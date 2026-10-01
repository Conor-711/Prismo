import XCTest
@testable import BSmart

@MainActor
final class TradeThesisRecoveryTests: XCTestCase {
    func testVerifiedActivityDoesNotResynchronize() async throws {
        var syncs = 0
        let value = try await TradeThesisVerificationWait.load(read: { 42 }, synchronize: { syncs += 1 })
        XCTAssertEqual(value, 42)
        XCTAssertEqual(syncs, 0)
    }

    func testPendingConcurrentVerifierIsReadAgainWithoutLosingItsOrder() async throws {
        var reads = 0, syncs = 0, pauses = 0
        let value = try await TradeThesisVerificationWait.load(read: {
            reads += 1
            if reads < 5 { throw TradeThesisError.pending }
            return "same verified trade"
        }, synchronize: { syncs += 1 }, pause: { _ in pauses += 1 })
        XCTAssertEqual(value, "same verified trade")
        XCTAssertEqual(syncs, 2)
        XCTAssertEqual(pauses, 2)
    }

    func testReadSideSyncFailureCanRecoverButMissingMigrationCannot() async throws {
        var reads = 0
        let value = try await TradeThesisVerificationWait.load(read: {
            reads += 1
            if reads == 1 { throw TradeThesisError.pending }
            return 7
        }, synchronize: { throw AccountAccessError.unavailable }, pause: { _ in })
        XCTAssertEqual(value, 7)
        do {
            _ = try await TradeThesisVerificationWait.load(read: { () -> Int in throw TradeThesisError.notReady },
                synchronize: { XCTFail("Missing schema must not start a sync") }, pause: { _ in XCTFail("No retry") })
            XCTFail("Must preserve migration error")
        } catch { XCTAssertEqual(error as? TradeThesisError, .notReady) }
    }

    func testPendingWaitIsBoundedAndCancellationStopsFurtherReads() async throws {
        var reads = 0, syncs = 0, delays: [Duration] = []
        do {
            _ = try await TradeThesisVerificationWait.load(read: { () -> Int in
                reads += 1; throw TradeThesisError.pending
            }, synchronize: { syncs += 1 }, pause: { delays.append($0) })
            XCTFail("Must not invent a verified item")
        } catch { XCTAssertEqual(error as? TradeThesisError, .pending) }
        XCTAssertEqual(reads, 8)
        XCTAssertEqual(syncs, 4)
        XCTAssertEqual(delays, [.seconds(1), .seconds(3), .seconds(6)])
        reads = 0
        do {
            _ = try await TradeThesisVerificationWait.load(read: { () -> Int in
                reads += 1; throw TradeThesisError.pending
            }, synchronize: {}, pause: { _ in throw CancellationError() })
            XCTFail("Cancellation must escape")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reads, 2)
    }

    func testAccountChangeAbortsVerificationRatherThanRetrying() async {
        var reads = 0
        do {
            _ = try await TradeThesisVerificationWait.load(read: { () -> Int in
                reads += 1; throw TradeThesisError.pending
            }, synchronize: { throw DeviceWalletError.accountChanged }, pause: { _ in XCTFail("No retry") })
            XCTFail("Must stop on account change")
        } catch { XCTAssertTrue(error is DeviceWalletError) }
        XCTAssertEqual(reads, 1)
    }

    func testDraftSurvivesEditorRecreationAndDiskReloadWithOriginalText() async throws {
        let folder = directory(), account = UUID(), trade = UUID()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TradeThesisDraftStore(directory: folder)
        for text in ["first", "first second", "  Original reasoning\n\n第二段 😀  "] {
            store.save(text, accountID: account, tradeID: trade)
        }
        XCTAssertEqual(store.cached(accountID: account, tradeID: trade), "  Original reasoning\n\n第二段 😀  ")
        await store.flush()
        XCTAssertTrue(store.failedKeys.isEmpty)
        let restored = try await TradeThesisDraftStore(directory: folder).load(accountID: account, tradeID: trade)
        XCTAssertEqual(restored, "  Original reasoning\n\n第二段 😀  ")
    }

    func testDraftsAreIsolatedByBothAccountAndTradeAndPublicationRemovesOnlyOne() async throws {
        let folder = directory(), account = UUID(), other = UUID(), trade = UUID(), next = UUID()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TradeThesisDraftStore(directory: folder)
        store.save("my draft", accountID: account, tradeID: trade)
        store.save("another trade", accountID: account, tradeID: next)
        store.save("another user", accountID: other, tradeID: trade)
        store.remove(accountID: account, tradeID: trade)
        await store.flush()
        let reader = TradeThesisDraftStore(directory: folder)
        let removed = try await reader.load(accountID: account, tradeID: trade)
        let otherTrade = try await reader.load(accountID: account, tradeID: next)
        let otherUser = try await reader.load(accountID: other, tradeID: trade)
        XCTAssertEqual(removed, "")
        XCTAssertEqual(otherTrade, "another trade")
        XCTAssertEqual(otherUser, "another user")
    }

    func testDeletionPreventsQueuedEditsFromResurrectingDrafts() async throws {
        let folder = directory(), account = UUID(), trade = UUID(), other = UUID()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TradeThesisDraftStore(directory: folder)
        store.save("private text", accountID: account, tradeID: trade)
        store.save("keep", accountID: other, tradeID: trade)
        try await store.erase(accountID: account)
        store.save("late text", accountID: account, tradeID: trade)
        await store.flush()
        XCTAssertNil(store.cached(accountID: account, tradeID: trade))
        let newStore = TradeThesisDraftStore(directory: folder)
        do { _ = try await newStore.load(accountID: account, tradeID: trade); XCTFail("Deleted account") }
        catch { }
        let kept = try await newStore.load(accountID: other, tradeID: trade)
        XCTAssertEqual(kept, "keep")
    }

    func testStorageFailureKeepsInMemoryDraftAndReportsFailure() async throws {
        let folder = directory(), account = UUID(), trade = UUID()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder)
        let store = TradeThesisDraftStore(directory: folder)
        store.save("never clear on failure", accountID: account, tradeID: trade)
        await store.flush()
        XCTAssertEqual(store.cached(accountID: account, tradeID: trade), "never clear on failure")
        XCTAssertTrue(store.failedKeys.contains(.init(accountID: account, tradeID: trade)))
    }

    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
}
