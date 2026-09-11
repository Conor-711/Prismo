import XCTest
@testable import BSmart

final class HyperliquidOrderFillTests: XCTestCase {
    typealias F = OrderFillFixture

    func testTimeQueryUsesNumericMillisecondsAndDisablesAggregation() throws {
        let data = try HyperliquidExecutionQuery.fills(owner: F.wallet.address, start: 1000, end: 65000).body()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "userFillsByTime")
        XCTAssertEqual(json["startTime"] as? Int, 1000)
        XCTAssertEqual(json["endTime"] as? Int, 65000)
        XCTAssertEqual(json["aggregateByTime"] as? Bool, false)
        XCTAssertNil(json["startTime"] as? String)
        for (start, end): (UInt64, UInt64) in [(2, 1), (0, 64001), (UInt64.max, UInt64.max)] {
            XCTAssertThrowsError(try HyperliquidExecutionQuery.fills(owner: F.wallet.address, start: start, end: end).body())
        }
        XCTAssertThrowsError(try HyperliquidExecutionQuery.fills(owner: "invalid", start: 0, end: 1).body())
    }

    func testExactAggregationIncludesFeesOnceAndDeduplicates() throws {
        let record = try F.record(), first = try F.fill(), second = try F.fill(["tid": 2, "sz": "1.5", "px": "220", "fee": "0.015"])
        let summary = try HyperliquidFillSummary(record: record, fills: [second, first, first])
        XCTAssertEqual(summary.fills.count, 2)
        XCTAssertEqual(summary.quantity.wire, "2.5")
        XCTAssertEqual(summary.averagePrice?.wire, "219.6")
        XCTAssertEqual(summary.fee, "0.025")
        XCTAssertTrue(summary.complete)
    }

    func testRebateIsSignedAndNotAnAdditionalCharge() throws {
        let record = try F.record(), first = try F.fill(["fee": "-0.005"])
        let second = try F.fill(["tid": 2, "sz": "1.5", "fee": "0.001"])
        let summary = try HyperliquidFillSummary(record: record, fills: [first, second])
        XCTAssertEqual(summary.fee, "-0.004")
        XCTAssertTrue(summary.complete)
    }

    func testMissingHistoryNeverMeansNoFeeOrCompletion() throws {
        let record = try F.record()
        let empty = try HyperliquidFillSummary(record: record, fills: [])
        XCTAssertFalse(empty.complete); XCTAssertNil(empty.averagePrice)
        let partial = try HyperliquidFillSummary(record: record, fills: [F.fill()])
        XCTAssertFalse(partial.complete)
        XCTAssertEqual(partial.quantity.wire, "1")
        XCTAssertEqual(partial.fee, "0.01")
    }

    func testPartialIOCIsCompleteAgainstItsAcknowledgedFilledQuantity() throws {
        let summary = try HyperliquidFillSummary(record: F.record(size: "1"), fills: [F.fill()])
        XCTAssertTrue(summary.complete, "Unfilled IOC quantity is not missing fill history")
    }

    func testWrongOrderCoinSideFeeTokenSizePriceOrTimestampRejected() throws {
        let record = try F.record(), order = try record.order.restored(wallet: F.wallet)
        let cases: [[String: Any]] = [["oid": 26], ["coin": "NVDA"], ["coin": "@107"], ["side": "A"],
            ["feeToken": "USDT"], ["feeToken": " USDC"], ["sz": "0"], ["sz": "1.0001"], ["sz": "3"],
            ["px": "222"], ["px": "0"], ["time": 1], ["time": order.expiresAfter + 2001],
            ["fee": "NaN"], ["fee": "1e-3"], ["closedPnl": "Infinity"], ["tid": 0],
            ["hash": "0x01"], ["cloid": "0x99"], ["builderFee": "0.001"]]
        for fields in cases {
            XCTAssertThrowsError(try F.fill(fields).validate(order: order, orderID: 25), "\(fields)")
        }
    }

    func testNoBuilderAndExplicitZeroAreAccepted() throws {
        let order = try HyperliquidQuoteFixture.order()
        try F.fill().validate(order: order, orderID: 25)
        try F.fill(["builderFee": "0.0"]).validate(order: order, orderID: 25)
    }

    func testConflictingTradeIDAndOverfilledTotalFailClosed() throws {
        let record = try F.record(), first = try F.fill()
        XCTAssertThrowsError(try HyperliquidFillSummary(record: record, fills: [first, F.fill(["fee": "0.1"])]))
        XCTAssertThrowsError(try HyperliquidFillSummary(record: record, fills: [first, F.fill(["tid": 2, "sz": "2"])]))
        XCTAssertThrowsError(try HyperliquidFillSummary(record: F.record(size: "1"), fills: [first, F.fill(["tid": 2])]))
    }

    func testDecoderExcludesOtherOrdersButRejectsConflictingCloidAttribution() throws {
        let data = try F.data([F.row(), F.row(["oid": 30, "coin": "BTC", "tid": 7])])
        XCTAssertEqual(try HyperliquidOrderFill.decode(data, record: F.record()).count, 1)
        let order = try HyperliquidQuoteFixture.order()
        let conflict = try F.data([F.row(["oid": 30, "cloid": order.cloid])])
        XCTAssertThrowsError(try HyperliquidOrderFill.decode(conflict, record: F.record()))
    }

    func testResponseBoundsAndMalformedPayloads() throws {
        let record = try F.record()
        for data in [Data("{}".utf8), Data("[{}]".utf8), Data(repeating: 32, count: 2_097_153),
                     try F.data(Array(repeating: F.row(), count: 2001))] {
            XCTAssertThrowsError(try HyperliquidOrderFill.decode(data, record: record))
        }
    }

    func testCloidIsAnExact128BitValueNotStringPrefix() throws {
        let full = "0x000000000000000000000000000001ab"
        XCTAssertTrue(HyperliquidOrderIdentifier.matches("0x1ab", full))
        XCTAssertTrue(HyperliquidOrderIdentifier.matches("0x01AB", full))
        for value: String? in [nil, "0x", "1ab", "0x1ag", "0x1ab ", "0x1ac", "0x" + String(repeating: "0", count: 33)] {
            XCTAssertFalse(HyperliquidOrderIdentifier.matches(value, full))
        }
    }

    func testJournalPersistsDeduplicatedEvidenceAcrossRestart() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (journal, _, id) = try await context.submitting()
        _ = try await journal.recordOrderResponse(id: id, response: F.ack(), wallet: F.wallet)
        let data = try F.data([F.row(), F.row(["tid": 2, "sz": "1.5", "fee": "0.02"])])
        try await journal.recordOrderFills(id: id, response: data, wallet: F.wallet)
        try await journal.recordOrderFills(id: id, response: data, wallet: F.wallet)
        let summaries = try await context.journal().orderFillSummaries(wallet: F.wallet)
        XCTAssertEqual(summaries[id]?.fills.count, 2)
        XCTAssertEqual(summaries[id]?.fee, "0.03")
        XCTAssertEqual(summaries[id]?.complete, true)
        let other = DeviceWalletSummary(accountID: UUID(), address: F.wallet.address, recoveryVerified: true)
        let hidden = try await journal.orderFillSummaries(wallet: other)
        XCTAssertTrue(hidden.isEmpty)
        await expectJournalFailure { try await journal.recordOrderFills(id: id, response: data, wallet: other) }
    }

    func testInvalidBatchNeverOverwritesPreviouslyVerifiedFees() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (journal, _, id) = try await context.submitting()
        _ = try await journal.recordOrderResponse(id: id, response: F.ack(), wallet: F.wallet)
        try await journal.recordOrderFills(id: id, response: F.data([F.row()]), wallet: F.wallet)
        let bad = try F.data([F.row(["fee": "4"]), F.row(["tid": 2, "sz": "1.5"])])
        await expectJournalFailure { try await journal.recordOrderFills(id: id, response: bad, wallet: F.wallet) }
        let summaries = try await context.journal().orderFillSummaries(wallet: F.wallet)
        XCTAssertEqual(summaries[id]?.fills.count, 1)
        XCTAssertEqual(summaries[id]?.fee, "0.01")
    }

    func testCancelledTaskAndClockRollbackPreserveObservedFills() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (journal, _, id) = try await context.submitting()
        _ = try await journal.recordOrderResponse(id: id, response: F.ack(), wallet: F.wallet)
        context.clock.advance(wall: -60, steady: .seconds(1))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await journal.recordOrderFills(id: id, response: F.data([F.row()]), wallet: F.wallet)
        }
        try await task.value
        let summaries = try await context.journal().orderFillSummaries(wallet: F.wallet)
        XCTAssertEqual(summaries[id]?.fills.count, 1)
    }

    func testUncertainOrderNeedsStatusProofBeforeAcceptingFills() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (journal, order, id) = try await context.submitting()
        _ = try await journal.recordOrderResponse(id: id, response: nil, wallet: F.wallet)
        await expectJournalFailure { try await journal.recordOrderFills(id: id, response: F.data([F.row()]), wallet: F.wallet) }
        _ = try await journal.reconcileOrder(id: id, response: context.status(order.order), wallet: F.wallet)
        try await journal.recordOrderFills(id: id, response: F.data([F.row(["sz": "2.5"])]), wallet: F.wallet)
        let summaries = try await journal.orderFillSummaries(wallet: F.wallet)
        XCTAssertEqual(summaries[id]?.complete, true)
    }

    func testMultipleBatchesFitJournalAndResumeAfterInterruptedCommit() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (journal, _, id) = try await context.submitting()
        _ = try await journal.recordOrderResponse(id: id, response: F.ack(), wallet: F.wallet)
        let data = try F.data((1...25).map { F.row(["tid": $0, "sz": "0.1", "fee": "0.001"]) })
        let failing = try context.journal { if $0 == .afterCommit { throw FundingJournalError.unavailable } }
        await expectJournalFailure { try await failing.recordOrderFills(id: id, response: data, wallet: F.wallet) }
        let resumed = try context.journal()
        let partial = try await resumed.orderFillSummaries(wallet: F.wallet)
        XCTAssertEqual(partial[id]?.fills.count, 8)
        try await resumed.recordOrderFills(id: id, response: data, wallet: F.wallet)
        let complete = try await context.journal().orderFillSummaries(wallet: F.wallet)
        XCTAssertEqual(complete[id]?.fills.count, 25)
        XCTAssertEqual(complete[id]?.fee, "0.025")
        XCTAssertEqual(complete[id]?.complete, true)
    }

    func testCancelledStatusDoesNotInferQuantityFromRemainingSize() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let (journal, quote, id) = try await context.submitting()
        _ = try await journal.recordOrderResponse(id: id, response: nil, wallet: F.wallet)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: context.status(quote.order)) as? [String: Any])
        var status = try XCTUnwrap(root["order"] as? [String: Any])
        status["status"] = "canceled"; root["order"] = status
        _ = try await journal.reconcileOrder(id: id, response: F.data(root), wallet: F.wallet)
        try await journal.recordOrderFills(id: id, response: F.data([F.row()]), wallet: F.wallet)
        let summaries = try await journal.orderFillSummaries(wallet: F.wallet)
        XCTAssertEqual(summaries[id]?.quantity.wire, "1")
        XCTAssertEqual(summaries[id]?.complete, false, "A closed order and sz=0 do not establish complete fill history")
    }
}

enum OrderFillFixture {
    static let wallet = HyperliquidTradingFixture.wallet
    static func data(_ value: Any) throws -> Data { try HyperliquidTradingFixture.data(value) }
    static func ack(size: String = "2.5") -> Data {
        Data("""
        {"status":"ok","response":{"type":"order","data":{"statuses":[{"filled":{"totalSz":"\(size)","avgPx":"219.6","oid":25}}]}}}
        """.utf8)
    }
    static func row(_ overrides: [String: Any] = [:]) -> [String: Any] {
        var result: [String: Any] = ["coin": HyperliquidTradingFixture.coin, "px": "219", "sz": "1", "side": "B",
            "fee": "0.01", "feeToken": "USDC", "closedPnl": "0", "hash": "0x" + String(repeating: "a", count: 64),
            "oid": 25, "tid": 1, "time": 1_789_084_801_000]
        result.merge(overrides) { _, new in new }; return result
    }
    static func fill(_ overrides: [String: Any] = [:]) throws -> HyperliquidOrderFill {
        try JSONDecoder().decode(HyperliquidOrderFill.self, from: data(row(overrides)))
    }
    static func record(size: String = "2.5") throws -> HyperliquidOrderRecord {
        .init(id: UUID(), order: try .init(HyperliquidQuoteFixture.order()), leverage: 10, marginMode: .cross,
              state: .filled, signature: nil, response: ack(size: size), updatedAt: HyperliquidTradingFixture.now)
    }
}
