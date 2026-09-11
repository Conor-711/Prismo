import XCTest
@testable import BSmart

final class HyperliquidOrderPreviewTests: XCTestCase {
    private typealias Q = HyperliquidQuoteFixture
    private typealias F = HyperliquidTradingFixture

    func testOnlyExactReadQueriesAndNoImplicitApproval() async throws {
        for builder in [nil, try HyperliquidBuilderFee(address: Q.recipient, tenthsOfBasisPoint: 10)] {
            var responses = [try Q.fees()]
            if builder != nil { responses.append(Data("10".utf8)) }
            responses.append(try Q.book())
            let reader = TradingCheckReaderStub(responses)
            let preview = try await run(reader, order: Q.order(builder: builder))
            var expected: [HyperliquidExecutionQuery] = [.fees(owner: F.wallet.address)]
            if let builder { expected.append(.builderApproval(owner: F.wallet.address, builder: builder.address)) }
            expected.append(.book(coin: F.coin))
            let calls = await reader.queries
            XCTAssertEqual(calls, expected)
            XCTAssertEqual(preview.builderApproval?.maximumTenthsOfBasisPoint, builder == nil ? nil : 10)
            XCTAssertEqual(preview.expiresAt, F.now.addingTimeInterval(5))
        }
    }
    func testInsufficientApprovalStopsBeforeBookAndNeverRaisesTheFeeCeiling() async throws {
        let reader = TradingCheckReaderStub([try Q.fees(), Data("9".utf8), try Q.book()])
        do { _ = try await run(reader, order: Q.order(builder: .init(address: Q.recipient, tenthsOfBasisPoint: 10)))
            XCTFail("Accepted insufficient approval")
        } catch { XCTAssertEqual(error as? HyperliquidQuoteError, .builderApprovalRequired) }
        let calls = await reader.queries; XCTAssertEqual(calls.count, 2)
    }
    func testMissingMetadataAndOverCapacityOrdersStopBeforeIO() async throws {
        for (market, size) in [(try Q.market(scale: nil), "2.5"), (try Q.market(), "9")] {
            let reader = TradingCheckReaderStub([])
            do { _ = try await run(reader, order: Q.order(size: size, market: market), account: Q.snapshot(market: market))
                XCTFail("Accepted invalid quote")
            } catch {}
            let calls = await reader.queries; XCTAssertTrue(calls.isEmpty)
        }
    }
    func testAgedBookExpiresOnEitherClockWithoutExtendingItsServerLifetime() async throws {
        let reader = TradingCheckReaderStub([try Q.fees(), try Q.book(at: F.now.addingTimeInterval(-4))])
        let result = try await run(reader)
        XCTAssertEqual(result.expiresAt, F.now.addingTimeInterval(1))
        XCTAssertNoThrow(try result.validate(wallet: F.wallet, now: F.now, continuousNow: F.instant))
        for (wall, steady): (Double, Duration) in [(1, .zero), (0, .seconds(1)), (-1, .zero), (0, .seconds(-1))] {
            XCTAssertThrowsError(try result.validate(wallet: F.wallet, now: F.now.addingTimeInterval(wall),
                continuousNow: F.instant.advanced(by: steady)))
        }
    }
    func testSlowIOCannotRefreshAnOldBookEvenIfTheWallClockFreezes() async throws {
        for (serverAge, latency): (Double, Double) in [(0, 5), (4, 1)] {
            let clock = TradingCheckClock()
            let reader = TradingCheckReaderStub([try Q.fees(), try Q.book(at: F.now.addingTimeInterval(-serverAge))]) {
                if $0 == 1 { clock.advance(steady: .seconds(latency)) }
            }
            do { _ = try await run(reader, clock: clock); XCTFail("Extended book lifetime") }
            catch { XCTAssertEqual(error as? HyperliquidQuoteError, .stale) }
        }
    }
    func testOrderExpiryAlsoBoundsTheContinuousReviewDeadline() async throws {
        let reader = TradingCheckReaderStub([try Q.fees(), try Q.book()])
        let result = try await run(reader, order: Q.order(expiry: 1_789_084_802_000))
        XCTAssertEqual(result.expiresAt, F.now.addingTimeInterval(1))
        XCTAssertThrowsError(try result.validate(wallet: F.wallet, now: F.now,
            continuousNow: F.instant.advanced(by: .seconds(1))))
    }
    func testExpiredAccountCannotBeRevivedByFreshBook() async throws {
        let clock = TradingCheckClock()
        let reader = TradingCheckReaderStub([try Q.fees(), try Q.book()]) {
            if $0 == 0 { clock.advance(steady: .seconds(15)) }
        }
        do { _ = try await run(reader, clock: clock); XCTFail("Accepted expired account") }
        catch { XCTAssertEqual(error as? HyperliquidTradingCheckError, .stale) }
        let calls = await reader.queries; XCTAssertEqual(calls.count, 1)
    }
    func testFailureAndLateCancellationDoNotPublishAPreview() async throws {
        let unavailable = TradingCheckReaderStub([])
        do { _ = try await run(unavailable); XCTFail("Ignored transport failure") }
        catch { XCTAssertEqual(error as? HyperliquidTradingCheckError, .unavailable) }
        let reader = TradingCheckReaderStub([try Q.fees(), try Q.book()]) { if $0 == 1 { withUnsafeCurrentTask { $0?.cancel() } } }
        let task = Task { try await self.run(reader) }
        do { _ = try await task.value; XCTFail("Published a late cancelled quote") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    private func run(_ reader: TradingCheckReaderStub, order: HyperliquidOrderIntent? = nil,
                     account: HyperliquidTradingSnapshot? = nil, clock: TradingCheckClock = .init()) async throws -> HyperliquidOrderPreview {
        try await HyperliquidOrderPreviewProvider(reader: reader, clock: { clock.now }, continuousClock: { clock.instant })
            .preview(order: order ?? Q.order(), wallet: F.wallet, account: account ?? Q.snapshot(clock: clock),
                     reviewedLeverage: 10, reviewedMarginMode: .cross)
    }
}
