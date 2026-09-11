import XCTest
@testable import BSmart

final class HyperliquidTradingSnapshotProviderTests: XCTestCase {
    private typealias F = HyperliquidTradingFixture

    func testEveryModeUsesExactMarketQueriesAndNeverTransfersOrChangesLeverage() async throws {
        for mode in HyperCoreAccountMode.allCases {
            let reader = TradingCheckReaderStub(try F.responses(mode: mode))
            let snapshot = try await provider(reader).snapshot(wallet: F.wallet, dex: "xyz", coin: F.coin)
            XCTAssertEqual(snapshot.mode, mode)
            XCTAssertEqual(snapshot.market.asset, 110000)
            XCTAssertEqual(snapshot.active.leverage.multiplier, 10)
            let queries = await reader.queries
            XCTAssertEqual(queries, [.dexs, .metadata(dex: "xyz"), .mode(owner: F.wallet.address),
                .active(owner: F.wallet.address, coin: F.coin), .positions(owner: F.wallet.address, dex: "xyz"),
                .active(owner: F.wallet.address, coin: F.coin), .positions(owner: F.wallet.address, dex: "xyz"),
                .mode(owner: F.wallet.address)])
        }
    }

    func testModeAndLeverageChangesAreRejected() async throws {
        var mode = try F.responses(); mode[7] = try F.data("disabled")
        await fails(mode, .stale)
        for raw: Any in ["future-mode", true, NSNull()] {
            var response = try F.responses(); response[2] = try F.data(raw)
            await fails(response, .invalidResponse)
        }
        var leverage = try F.responses(); leverage[5] = try F.active(leverage: F.leverage("cross", 20))
        await fails(leverage, .leverageChanged)
        var margin = try F.responses(); margin[5] = try F.active(leverage: F.leverage("isolated"))
        await fails(margin, .leverageChanged)
        var mismatch = try F.responses(positionRows: [F.row(leverage: F.leverage("cross", 20))])
        await fails(mismatch, .leverageChanged)
        mismatch[4] = try F.positions(); mismatch[6] = try F.positions(rows: [F.row(leverage: F.leverage("cross", 20))])
        await fails(mismatch, .leverageChanged)
    }

    func testPositionOpensClosesGrowsOrFlipsDuringReadCannotBeUsed() async throws {
        for final in [[], [F.row(size: "-2.4")], [F.row(size: "-2.6")], [F.row(size: "2.5")]] {
            var responses = try F.responses(positionRows: [F.row()]); responses[6] = try F.positions(rows: final)
            await fails(responses, .stale)
        }
        var opened = try F.responses(); opened[6] = try F.positions(rows: [F.row()])
        await fails(opened, .stale)
        var regressed = try F.responses(); regressed[6] = try F.positions(at: F.now.addingTimeInterval(-1))
        await fails(regressed, .stale)
    }

    func testFinalServerTimeIsRetainedAndExpiresWhileCallerReviews() async throws {
        var responses = try F.responses()
        responses[4] = try F.positions(at: F.now.addingTimeInterval(-14))
        responses[6] = responses[4]
        let snapshot = try await provider(TradingCheckReaderStub(responses)).snapshot(wallet: F.wallet, dex: "xyz", coin: F.coin)
        XCTAssertEqual(snapshot.expiresAt, F.now.addingTimeInterval(1))
        XCTAssertThrowsError(try snapshot.validate(wallet: F.wallet, now: snapshot.expiresAt,
                                                   continuousNow: F.instant.advanced(by: .seconds(1))))
        let clock = TradingCheckClock()
        let delayed = TradingCheckReaderStub(responses) { if $0 == 7 { clock.advance(wall: 1, steady: .seconds(1)) } }
        do { _ = try await provider(delayed, clock: clock).snapshot(wallet: F.wallet, dex: "xyz", coin: F.coin)
            XCTFail("Reissued expired positions after final IO")
        } catch { XCTAssertEqual(error as? HyperliquidTradingCheckError, .stale) }
    }

    func testWallAndMonotonicDeadlinesCoverIOAndRollback() async throws {
        for (wall, steady): (Double, Duration) in [(15, .zero), (0, .seconds(15)), (-1, .zero), (0, .seconds(-1))] {
            let clock = TradingCheckClock()
            let reader = TradingCheckReaderStub(try F.responses()) { if $0 == 0 { clock.advance(wall: wall, steady: steady) } }
            do { _ = try await provider(reader, clock: clock).snapshot(wallet: F.wallet, dex: "xyz", coin: F.coin)
                XCTFail("Accepted expired/rolled-back IO")
            } catch { XCTAssertEqual(error as? HyperliquidTradingCheckError, .stale) }
            let calls = await reader.queries
            XCTAssertEqual(calls.count, 1)
        }
    }

    func testForeignWalletAndUnsupportedCollateralStopBeforeAccountQueries() async throws {
        let reader = TradingCheckReaderStub(try F.responses())
        for wallet in [DeviceWalletSummary(accountID: F.wallet.accountID, address: "0x0", recoveryVerified: true),
                       .init(accountID: F.wallet.accountID, address: "0x" + String(repeating: "0", count: 40), recoveryVerified: false)] {
            do { _ = try await provider(reader).snapshot(wallet: wallet, dex: "xyz", coin: F.coin); XCTFail("Invalid wallet") }
            catch { XCTAssertEqual(error as? HyperliquidTradingCheckError, .accountChanged) }
        }
        let calls = await reader.queries; XCTAssertTrue(calls.isEmpty)
        var responses = try F.responses(); responses[1] = try F.metadata(collateral: 7)
        let other = TradingCheckReaderStub(responses)
        do { _ = try await provider(other).snapshot(wallet: F.wallet, dex: "xyz", coin: F.coin); XCTFail("Wrong collateral") }
        catch { XCTAssertEqual(error as? HyperliquidTradingCheckError, .unsupportedCollateral) }
        let otherCalls = await other.queries; XCTAssertEqual(otherCalls.count, 2)
    }

    func testFailureAndCancellationNeverPublishASnapshot() async throws {
        for stop in [0, 3, 7] {
            let reader = TradingCheckReaderStub(try F.responses()) { if $0 == stop { throw HyperliquidTradingCheckError.unavailable } }
            do { _ = try await provider(reader).snapshot(wallet: F.wallet, dex: "xyz", coin: F.coin); XCTFail("Swallowed failure") }
            catch { XCTAssertEqual(error as? HyperliquidTradingCheckError, .unavailable) }
        }
        let reader = TradingCheckReaderStub(try F.responses()) { index in
            if index == 7 { withUnsafeCurrentTask { $0?.cancel() } }
        }
        let source = provider(reader)
        let task = Task { try await source.snapshot(wallet: F.wallet, dex: "xyz", coin: F.coin) }
        do { _ = try await task.value; XCTFail("Late cancelled response became a snapshot") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    private func provider(_ reader: TradingCheckReaderStub, clock: TradingCheckClock = .init()) -> HyperliquidTradingSnapshotProvider {
        .init(reader: reader, clock: { clock.now }, continuousClock: { clock.instant })
    }
    private func fails(_ responses: [Data], _ expected: HyperliquidTradingCheckError) async {
        do { _ = try await provider(TradingCheckReaderStub(responses)).snapshot(wallet: F.wallet, dex: "xyz", coin: F.coin)
            XCTFail("Accepted invalid snapshot")
        } catch { XCTAssertEqual(error as? HyperliquidTradingCheckError, expected) }
    }
}
