import XCTest
@testable import BSmart

final class AccountBalanceHistoryTests: XCTestCase {
    func testAccountBalanceIncludesCashAndPerpsEquity() throws {
        XCTAssertEqual(try XCTUnwrap(CoreBalanceFixture.snapshot().accountBalanceValue), 59.94207, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(CoreBalanceFixture.snapshot(mode: .default).accountBalanceValue), 57.57207, accuracy: 0.00001)
    }

    func testHistoryUsesOnlyVerifiedAccountAndWallet() throws {
        let suite = "bsmart.balance-test.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let wallet = CoreBalanceFixture.wallet
        let snapshot = try CoreBalanceFixture.snapshot()
        XCTAssertEqual(AccountBalanceHistory.record(snapshot, wallet: wallet, defaults: defaults).count, 1)
        XCTAssertEqual(AccountBalanceHistory.load(wallet: wallet, now: snapshot.checkedAt, defaults: defaults).count, 1)
        let other = DeviceWalletSummary(accountID: UUID(), address: wallet.address, recoveryVerified: true)
        XCTAssertTrue(AccountBalanceHistory.load(wallet: other, now: snapshot.checkedAt, defaults: defaults).isEmpty)
        XCTAssertTrue(AccountBalanceHistory.record(snapshot, wallet: other, defaults: defaults).isEmpty)
    }

    func testOfficialPortfolioPeriodsRemainSeparateAndValidated() throws {
        let now = CoreBalanceFixture.now
        let start = Int(now.addingTimeInterval(-3_600).timeIntervalSince1970 * 1_000)
        let response: FundingRPCValue = .array([
            .array([.string("day"), .object(["accountValueHistory": .array([
                .array([.integer(start), .string("1")])
            ])])]),
            .array([.string("week"), .object(["accountValueHistory": .array([
                .array([.integer(start), .string("1.77")]),
                .array([.integer(start + 60_000), .string("1.80")])
            ])])]),
            .array([.string("month"), .object(["accountValueHistory": .array([
                .array([.integer(start), .string("2.00")])
            ])])]),
            .array([.string("allTime"), .object(["accountValueHistory": .array([
                .array([.integer(start), .string("3.00")])
            ])])])
        ])
        let points = try AccountBalanceHistory.parsePortfolio(response, now: now)
        XCTAssertEqual(points[.day]?.map(\.value), [1])
        XCTAssertEqual(points[.week]?.map(\.value), [1.77, 1.80])
        XCTAssertEqual(points[.month]?.map(\.value), [2])
        XCTAssertEqual(points[.all]?.map(\.value), [3])
        XCTAssertThrowsError(try AccountBalanceHistory.parsePortfolio(.array([
            .array([.string("week"), .object(["accountValueHistory": .array([
                .array([.integer(start), .string("NaN")])
            ])])])
        ]), now: now))
    }

    func testLocalFallbackRespectsSelectedPeriod() {
        let now = CoreBalanceFixture.now
        let history = [
            PortfolioValuePoint(timestamp: now.addingTimeInterval(-14 * 86_400), value: 1),
            PortfolioValuePoint(timestamp: now.addingTimeInterval(-2 * 86_400), value: 2),
            PortfolioValuePoint(timestamp: now, value: 3)
        ]
        XCTAssertEqual(AccountBalancePeriod.day.localPoints(in: history, now: now).map(\.value), [3])
        XCTAssertEqual(AccountBalancePeriod.week.localPoints(in: history, now: now).map(\.value), [2, 3])
        XCTAssertEqual(AccountBalancePeriod.all.localPoints(in: history, now: now).map(\.value), [1, 2, 3])
    }
}
