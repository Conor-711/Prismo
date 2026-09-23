import XCTest
@testable import BSmart

final class HyperliquidOrderAccountObservationTests: XCTestCase {
    private typealias F = HyperliquidTradingFixture

    func testFiveIndependentReadsOverlapInOneRound() async throws {
        let reader = OrderObservationReader()
        let snapshot = try await provider(reader).snapshot(wallet: F.wallet, dex: "xyz", coin: F.coin)
        let peak = await reader.peak, count = await reader.count
        XCTAssertEqual(peak, 5); XCTAssertEqual(count, 5)
        XCTAssertEqual(snapshot.owner, F.wallet.address)
        XCTAssertEqual(snapshot.market.coin, F.coin)
        XCTAssertEqual(snapshot.requestedAt, F.now)
        XCTAssertEqual(snapshot.requestedContinuousAt, F.instant)
    }

    func testUnknownModeMismatchedLeverageStalePositionAndForeignOwnerFailClosed() async throws {
        for (query, data) in [
            (HyperliquidExecutionQuery.mode(owner: F.wallet.address), try F.data("unknown")),
            (.positions(owner: F.wallet.address, dex: "xyz"), try F.positions(rows: [F.row(leverage: F.leverage("cross", 20))])),
            (.positions(owner: F.wallet.address, dex: "xyz"), try F.positions(at: F.now.addingTimeInterval(-16))),
            (.active(owner: F.wallet.address, coin: F.coin), try F.active(overrides: ["user": "0x" + String(repeating: "1", count: 40)]))
        ] {
            let reader = OrderObservationReader(override: (query, data))
            do { _ = try await provider(reader).snapshot(wallet: F.wallet, dex: "xyz", coin: F.coin); XCTFail("Invalid observation") }
            catch { XCTAssertTrue(error is HyperliquidTradingCheckError) }
        }
    }

    func testDeadlineIncludesNetworkTimeAndCannotBeResetByFrozenClock() async throws {
        for (wall, steady): (Double, Duration) in [(11, .zero), (0, .seconds(11)), (-1, .zero)] {
            let clock = TradingCheckClock()
            let reader = OrderObservationReader(afterRead: { clock.advance(wall: wall, steady: steady) })
            do {
                _ = try await provider(reader, clock: clock).snapshot(wallet: F.wallet, dex: "xyz", coin: F.coin)
                XCTFail("Stale observation accepted")
            } catch { XCTAssertEqual(error as? HyperliquidTradingCheckError, .stale) }
        }
    }

    func testCancellationCannotProduceAnObservation() async throws {
        let reader = OrderObservationReader()
        let task = Task { try await provider(reader).snapshot(wallet: F.wallet, dex: "xyz", coin: F.coin) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled observation accepted") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    private func provider(_ reader: OrderObservationReader, clock: TradingCheckClock = .init()) -> HyperliquidOrderAccountObservation {
        .init(reader: reader, clock: { clock.now }, continuousClock: { clock.instant })
    }
}

private actor OrderObservationReader: HyperliquidExecutionReading {
    private let underlying = OrderStoreReader()
    private let override: (HyperliquidExecutionQuery, Data)?
    private let afterRead: @Sendable () -> Void
    private var inFlight = 0
    private(set) var peak = 0
    private(set) var count = 0
    init(override: (HyperliquidExecutionQuery, Data)? = nil, afterRead: @escaping @Sendable () -> Void = {}) {
        self.override = override; self.afterRead = afterRead
    }
    func read(_ query: HyperliquidExecutionQuery) async throws -> Data {
        inFlight += 1; count += 1; peak = max(peak, inFlight)
        defer { inFlight -= 1 }
        try await Task.sleep(for: .milliseconds(20))
        if query == .dexs { afterRead() }
        if let override, query == override.0 { return override.1 }
        return try await underlying.read(query)
    }
}
