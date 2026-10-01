import XCTest
@testable import BSmart

final class SubjectOptionInterpretationTests: XCTestCase {
    func testCallChangesDescribeExposureNotReversal() throws {
        XCTAssertEqual(try interpretation("CALL option", "increased").titleKey, "Bullish exposure increased")
        XCTAssertEqual(try interpretation("call OPTION", "new").titleKey, "Bullish exposure increased")
        XCTAssertEqual(try interpretation("CALL option", "reduced").titleKey, "Bullish exposure reduced")
        XCTAssertEqual(try interpretation("CALL option", "held").titleKey, "Bullish option exposure reported")
    }

    func testPutChangesRetainHedgingAmbiguity() throws {
        XCTAssertEqual(try interpretation("PUT option", "increased").titleKey, "Bearish or hedging exposure increased")
        XCTAssertEqual(try interpretation("PUT option", "new").kind, .put)
        XCTAssertEqual(try interpretation("PUT option", "reduced").titleKey, "Bearish or hedging exposure reduced")
        XCTAssertEqual(try interpretation("PUT option", "held").titleKey, "Bearish or hedging option exposure reported")
    }

    func testOmissionNeverClaimsClosingOrDirectionReversal() throws {
        for kind in ["CALL option", "PUT option"] {
            let value = try interpretation(kind, "no_longer_reported")
            XCTAssertEqual(value.titleKey, "Option position no longer reported")
            XCTAssertTrue(value.explanationKey.contains("does not confirm"))
        }
    }

    func testMissingOrUnrecognizedTypeAndActionStayUnknown() throws {
        XCTAssertEqual(try interpretation(nil, "increased").titleKey, "Direction cannot be confirmed")
        XCTAssertEqual(try interpretation("Possibly Call", "increased").kind, .unknown)
        XCTAssertEqual(try interpretation("PUT option", "unexpected").titleKey, "Direction cannot be confirmed")
    }

    func testStockAndSampleHoldingsDoNotReceiveOptionInterpretation() throws {
        XCTAssertNil(SubjectOptionInterpretation(event: try event(nil, "held", ticker: "TSLA", underlying: nil)))
        XCTAssertNil(SubjectOptionInterpretation(event: try event("CALL option", "increased", sample: true)))
    }

    func testSynchronizationRetainsExactSubjectReferenceForStockAndUnderlying() throws {
        for value in [try event("CALL option", "increased"), try event(nil, "held", ticker: "TSLA", underlying: nil)] {
            let source = try XCTUnwrap(value.syncSource)
            XCTAssertEqual(source.ticker, "TSLA")
            XCTAssertEqual(source.subjectID, "celebrity:investor")
            XCTAssertEqual(source.subjectEventID, "filing-1")
            XCTAssertNil(source.opinionID)
        }
        XCTAssertNil(try event(nil, "held", ticker: nil, underlying: nil).syncSource)
    }

    func testChineseSummaryStaysShort() throws {
        let old = BSmartLocalization.language
        BSmartLocalization.configure(.simplifiedChinese)
        defer { BSmartLocalization.configure(old) }
        for kind in ["CALL option", "PUT option"] {
            for action in ["new", "increased", "reduced", "held", "no_longer_reported"] {
                XCTAssertLessThanOrEqual(try interpretation(kind, action).titleKey.bSmartLocalized.count, 10)
            }
        }
    }

    private func interpretation(_ summary: String?, _ action: String) throws -> SubjectOptionInterpretation {
        try XCTUnwrap(SubjectOptionInterpretation(event: event(summary, action)))
    }

    private func event(_ summary: String?, _ action: String, ticker: String? = nil,
                       underlying: String? = "TSLA", sample: Bool = false) throws -> TodaySubjectEvent {
        var fields: [String: Any] = ["id": "filing-1", "subjectID": "celebrity:investor", "type": "holding",
                                    "assetName": "TESLA INC", "action": action, "isSample": sample,
                                    "occurredDay": "2026-06-30", "displayDay": "2026-09-02"]
        fields["summary"] = summary
        fields["ticker"] = ticker
        fields["underlyingTicker"] = underlying
        return try JSONDecoder().decode(TodaySubjectEvent.self, from: JSONSerialization.data(withJSONObject: fields))
    }
}
