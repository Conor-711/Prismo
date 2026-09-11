import XCTest
@testable import BSmart

final class CCTPDepositQuoteTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    func testLiveSchemaUsesExactFeesAndSeparateCeiling() throws {
        let schedule = try CCTPFeeSchedule.decode(Data(Self.response.utf8), receivedAt: now)
        let quote = try CCTPDepositQuote(amount: "10", schedule: schedule, now: now)
        XCTAssertEqual(schedule.protocolRateMillionths, 0)
        XCTAssertEqual(quote.protocolFeeUnits, 0)
        XCTAssertEqual(quote.forwardingFeeUnits, 200_000)
        XCTAssertEqual(quote.maximumFeeUnits, 240_000)
        XCTAssertEqual(quote.estimatedCreditUnits, 9_800_000)
        XCTAssertEqual(quote.minimumCreditUnits, 9_760_000)
        XCTAssertEqual(quote.expiresAt, now.addingTimeInterval(60))
    }

    func testProtocolBasisPointsRoundUpNotToBinaryFloatOrNearest() throws {
        let data = Data(Self.response.replacingOccurrences(of: "\"minimumFee\":0", with: "\"minimumFee\":1.4").utf8)
        let schedule = try CCTPFeeSchedule.decode(data, receivedAt: now)
        XCTAssertEqual(schedule.protocolRateMillionths, 140)
        let quote = try CCTPDepositQuote(amount: "2.000001", schedule: schedule, now: now)
        XCTAssertEqual(quote.protocolFeeUnits, 281)
        XCTAssertEqual(quote.maximumFeeUnits, 240_338)
    }

    func testRejectsMissingDuplicateFractionalOrNegativeFees() {
        let bad = ["[]", "{}", "null", "[{}]",
                   Self.response.replacingOccurrences(of: "1000", with: "2000"),
                   "[" + String(Self.response.dropFirst().dropLast()) + "," + String(Self.response.dropFirst().dropLast()) + "]",
                   Self.response.replacingOccurrences(of: "\"minimumFee\":0", with: "\"minimumFee\":-1"),
                   Self.response.replacingOccurrences(of: "\"minimumFee\":0", with: "\"minimumFee\":0.001"),
                   Self.response.replacingOccurrences(of: "\"minimumFee\":0", with: "\"minimumFee\":10001"),
                   Self.response.replacingOccurrences(of: "\"high\":200000", with: "\"high\":199999"),
                   Self.response.replacingOccurrences(of: "\"high\":200000", with: "\"high\":0.5"),
                   Self.response.replacingOccurrences(of: "\"high\":200000", with: "\"high\":-1"),
                   Self.response.replacingOccurrences(of: "\"forwardFee\"", with: "\"otherFee\"")]
        for response in bad {
            XCTAssertThrowsError(try CCTPFeeSchedule.decode(Data(response.utf8), receivedAt: now), response)
        }
    }

    func testRejectsOversizedPayloadAndUnsafeNumericDomain() {
        XCTAssertThrowsError(try CCTPFeeSchedule.decode(Data(repeating: 32, count: 16_385), receivedAt: now))
        for schedule in [
            CCTPFeeSchedule(protocolRateMillionths: UInt64.max, forwardingFeeUnits: 0, receivedAt: now),
            CCTPFeeSchedule(protocolRateMillionths: 0, forwardingFeeUnits: UInt64.max, receivedAt: now)
        ] { XCTAssertThrowsError(try CCTPDepositQuote(amount: "10", schedule: schedule, now: now)) }
    }

    func testQuoteCannotOutliveScheduleOrSurviveClockRollback() throws {
        let schedule = try CCTPFeeSchedule.decode(Data(Self.response.utf8), receivedAt: now)
        XCTAssertNoThrow(try schedule.validate(now: now.addingTimeInterval(59)))
        for seconds in [-1.0, 60, 1000] {
            XCTAssertThrowsError(try CCTPDepositQuote(amount: "10", schedule: schedule, now: now.addingTimeInterval(seconds)))
        }
        XCTAssertEqual(try CCTPDepositQuote(amount: "10", schedule: schedule,
            now: now.addingTimeInterval(59)).expiresAt, now.addingTimeInterval(60))
    }

    func testResidualGuardIsNotLegacyMinimumOrUpfrontActivationDeduction() throws {
        let schedule = try CCTPFeeSchedule.decode(Data(Self.response.utf8), receivedAt: now)
        let quote = try CCTPDepositQuote(amount: "1.24", schedule: schedule, now: now)
        XCTAssertEqual(quote.minimumCreditUnits, 1_000_000)
        XCTAssertEqual(quote.estimatedCreditUnits, 1_040_000)
        XCTAssertThrowsError(try CCTPDepositQuote(amount: "1.239999", schedule: schedule, now: now))
        XCTAssertNoThrow(try CCTPDepositQuote(amount: "4.99", schedule: schedule, now: now))
    }

    func testRejectsZeroScientificNotationOverflowAndImplicitBatching() throws {
        let schedule = try CCTPFeeSchedule.decode(Data(Self.response.utf8), receivedAt: now)
        for amount in ["0", "-1", "5e2", "1,23", "2.0000001", "10000000.000001", String(UInt64.max)] {
            XCTAssertThrowsError(try CCTPDepositQuote(amount: amount, schedule: schedule, now: now))
        }
        XCTAssertNoThrow(try CCTPDepositQuote(amount: "10000000", schedule: schedule, now: now))
    }

    static let response = #"[{"finalityThreshold":1000,"minimumFee":0,"forwardFee":{"low":200000,"med":200000,"high":200000}}]"#
}
