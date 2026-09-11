import XCTest
@testable import BSmart

final class HyperCoreBalanceTests: XCTestCase {
    func testAmountsPreserveExactEightDecimalsAndSignedEquity() throws {
        for (input, expected) in [("59.942070", "59.94207"), ("0.00000001", "0.00000001"),
                                  ("184467440737.09551615", "184467440737.09551615"), ("-0.0", "0"), ("-42.25", "-42.25")] {
            XCTAssertEqual(try HyperCoreUSDCAmount(input, signed: true).formatted, expected)
        }
        XCTAssertEqual(try HyperCoreUSDCAmount("0.00000001").units, FundingQuantity(1))
        for input in ["", "-1", "+1", " 1", "1 ", "1e2", "NaN", "01", ".1", "1.", "1..2", "1,234", "1.000000001",
                      "184467440737.09551616", "١", String(repeating: "9", count: 100)] {
            XCTAssertThrowsError(try HyperCoreUSDCAmount(input), input)
        }
    }

    func testUSDCIdentityEmptyBalancesAndInconsistentValues() throws {
        let (total, held) = try HyperCoreBalanceProvider.spot(CoreBalanceFixture.spot)
        XCTAssertEqual(total.formatted, "59.94207"); XCTAssertEqual(held.formatted, "17.920306")
        let empty = try HyperCoreBalanceProvider.spot(.object(["balances": .array([])]))
        XCTAssertEqual(empty.0.formatted, "0")
        guard case .object(let root) = CoreBalanceFixture.spot, case .array(let rows) = root["balances"],
              case .object(let fields) = rows[0] else { return XCTFail("Invalid fixture") }
        for delta: [String: FundingRPCValue] in [
            ["token": .integer(1)], ["token": .bool(false)], ["coin": .string("USDC.e")], ["coin": .string("usdc")],
            ["total": .integer(60)], ["total": .string("-1")], ["hold": .string("60")], ["hold": .null]
        ] {
            var changed = fields; changed.merge(delta) { _, new in new }
            XCTAssertThrowsError(try HyperCoreBalanceProvider.spot(.object(["balances": .array([.object(changed)])])))
        }
        for bad: FundingRPCValue in [.null, .object([:]), .object(["balances": .null]),
                                     .object(["balances": .array(rows + rows)]),
                                     .object(["balances": .array(Array(repeating: rows[0], count: 2_049))])] {
            XCTAssertThrowsError(try HyperCoreBalanceProvider.spot(bad))
        }
    }

    func testPerpsAllowsNegativeEquityButNotNegativeWithdrawable() throws {
        let result = try HyperCoreBalanceProvider.perps(CoreBalanceFixture.perps)
        XCTAssertEqual(result.equity.formatted, "-2.37"); XCTAssertEqual(result.withdrawable.formatted, "0")
        guard case .object(var fields) = CoreBalanceFixture.perps else { return XCTFail("Fixture") }
        for value: FundingRPCValue in [.null, .integer(2), .string("-1"), .string("1e5")] {
            fields["withdrawable"] = value
            XCTAssertThrowsError(try HyperCoreBalanceProvider.perps(.object(fields)))
        }
    }

    func testModeControlsTheBalanceSourceAndNeverCombinesAccounts() async throws {
        for mode in HyperCoreAccountMode.allCases {
            let reader = CoreBalanceReaderStub(mode: mode)
            let result = try await HyperCoreBalanceProvider(reader: reader, clock: { CoreBalanceFixture.now })
                .snapshot(wallet: CoreBalanceFixture.wallet)
            XCTAssertEqual(result.mode, mode); XCTAssertEqual(result.usdc.formatted, "59.94207")
            XCTAssertEqual(result.perps == nil, mode.usesSharedBalance)
            let calls = await reader.calls
            XCTAssertEqual(calls.map(\.0), mode.usesSharedBalance ? [.mode, .spot, .mode] : [.mode, .spot, .perps, .mode])
            XCTAssertTrue(calls.allSatisfy { $0.1 == CoreBalanceFixture.wallet.address })
        }
    }

    func testUnknownChangingModeStaleOrForeignSnapshotsAreRejected() async throws {
        for mode: FundingRPCValue in [.string("future-mode"), .bool(false), .null] {
            XCTAssertThrowsError(try HyperCoreBalanceProvider.mode(mode))
        }
        let changed = CoreBalanceReaderStub(mode: .unifiedAccount, finalMode: .disabled)
        do { _ = try await HyperCoreBalanceProvider(reader: changed, clock: { CoreBalanceFixture.now }).snapshot(wallet: CoreBalanceFixture.wallet)
            XCTFail("Accepted changed mode") } catch { XCTAssertEqual(error as? HyperCoreBalanceError, .stale) }
        let snapshot = try CoreBalanceFixture.snapshot()
        for date in [CoreBalanceFixture.now.addingTimeInterval(-1), snapshot.expiresAt, snapshot.expiresAt.addingTimeInterval(1)] {
            XCTAssertThrowsError(try snapshot.validate(wallet: CoreBalanceFixture.wallet, now: date))
        }
        XCTAssertThrowsError(try snapshot.validate(wallet: .init(accountID: UUID(), address: snapshot.owner, recoveryVerified: true), now: snapshot.checkedAt))
        for time in [CoreBalanceFixture.now.addingTimeInterval(-31), CoreBalanceFixture.now.addingTimeInterval(16)] {
            let reader = CoreBalanceReaderStub(mode: .disabled, perpsTime: time)
            do { _ = try await HyperCoreBalanceProvider(reader: reader, clock: { CoreBalanceFixture.now }).snapshot(wallet: CoreBalanceFixture.wallet)
                XCTFail("Accepted stale or future server time") } catch { XCTAssertEqual(error as? HyperCoreBalanceError, .stale) }
        }
    }
}

enum CoreBalanceFixture {
    static let now = Date(timeIntervalSince1970: 1_789_063_365)
    static let wallet = PreflightTestFixture.wallet
    static let spot: FundingRPCValue = .object(["balances": .array([
        .object(["coin": .string("USDC"), "token": .integer(0), "total": .string("59.94207"), "hold": .string("17.920306"), "entryNtl": .string("0.0")]),
        .object(["coin": .string("HYPE"), "token": .integer(150), "total": .string("2"), "hold": .string("0")])
    ])])
    static var perps: FundingRPCValue { perps(at: now) }
    static func perps(at time: Date) -> FundingRPCValue {
        .object(["marginSummary": .object(["accountValue": .string("-2.37")]), "withdrawable": .string("0.0"),
                 "time": .integer(Int(time.timeIntervalSince1970 * 1_000))])
    }
    static func snapshot(mode: HyperCoreAccountMode = .unifiedAccount, time: Date = now) throws -> HyperCoreBalanceSnapshot {
        try .init(accountID: wallet.accountID, owner: wallet.address, mode: mode, usdc: HyperCoreUSDCAmount("59.94207"),
                  held: HyperCoreUSDCAmount("17.920306"), perps: mode.usesSharedBalance ? nil : HyperCoreBalanceProvider.perps(perps(at: time)),
                  requestedAt: time, checkedAt: time)
    }
}

actor CoreBalanceReaderStub: HyperCoreBalanceReading {
    let mode: HyperCoreAccountMode
    let finalMode: HyperCoreAccountMode
    let perpsTime: Date
    private(set) var calls: [(HyperCoreBalanceQuery, String)] = []
    init(mode: HyperCoreAccountMode, finalMode: HyperCoreAccountMode? = nil, perpsTime: Date = CoreBalanceFixture.now) {
        self.mode = mode; self.finalMode = finalMode ?? mode; self.perpsTime = perpsTime
    }
    func read(_ query: HyperCoreBalanceQuery, owner: String) async throws -> FundingRPCValue {
        calls.append((query, owner))
        switch query {
        case .mode: return .string((calls.count == 1 ? mode : finalMode).rawValue)
        case .spot: return CoreBalanceFixture.spot
        case .perps: return CoreBalanceFixture.perps(at: perpsTime)
        }
    }
}
