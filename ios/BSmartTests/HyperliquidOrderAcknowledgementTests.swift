import XCTest
@testable import BSmart

final class HyperliquidOrderAcknowledgementTests: XCTestCase {
    func testCompleteFill() throws {
        let result = try decode(status: fill(size: "3.125", price: "230.89"))
        guard case let .filled(value) = result else { return XCTFail("Expected a fill") }
        XCTAssertEqual(value.orderID, 77747314)
        XCTAssertEqual(value.size.wire, "3.125")
        XCTAssertTrue(value.isComplete)
    }

    func testPartialIOCIsNotACompleteFill() throws {
        let result = try decode(status: fill(size: "0.1", price: "230.8981234567"))
        guard case let .filled(value) = result else { return XCTFail("Expected a partial fill") }
        XCTAssertFalse(value.isComplete)
        XCTAssertEqual(value.averagePrice.wire, "230.8981234567")
    }

    func testHTTP200OrderRejectionIsNotSuccess() throws {
        XCTAssertEqual(try decode(status: #"{"error":"Insufficient margin"}"#), .rejected("Insufficient margin"))
        XCTAssertEqual(try HyperliquidOrderAcknowledgement.decode(Data(#"{"status":"err","response":"Invalid nonce"}"#.utf8),
            for: HyperliquidOrderTestSupport.order()), .rejected("Invalid nonce"))
    }

    func testMalformedRestingPendingAndContradictoryStatusesAreUnknown() {
        for status in [#"{"resting":{"oid":1}}"#, #""waitingForFill""#, #""success""#,
                       #"{"filled":null}"#, #"{"error":""}"#, #"{}"#,
                       #"{"error":"Insufficient margin","filled":{"totalSz":"1","avgPx":"230","oid":1}}"#,
                       #"{"filled":{"totalSz":"1","avgPx":"230","oid":1},"unknown":true}"#] {
            XCTAssertThrowsError(try decode(status: status), status) {
                XCTAssertEqual($0 as? HyperliquidExecutionError, .invalidAcknowledgement)
            }
        }
    }

    func testWrongSizePriceAndIDCannotBeClaimedAsFill() {
        for status in [fill(size: "3.126"), fill(size: "0"), fill(size: "1.0001"),
                       fill(price: "230.901"), fill(price: "0"), fill(price: "NaN"),
                       fill(oid: "0"), fill(oid: "-1"), fill(oid: "true"), fill(oid: "1.5")] {
            XCTAssertThrowsError(try decode(status: status), status)
        }
    }

    func testSellPriceFloorIsRespected() throws {
        let order = try HyperliquidOrderTestSupport.order(side: .sell)
        XCTAssertNoThrow(try decode(status: fill(price: "231"), order: order))
        XCTAssertThrowsError(try decode(status: fill(price: "230.89"), order: order))
    }

    func testMissingExtraOrWrongActionResponsesAreUnknown() throws {
        for response in [#"{"status":"ok","response":{"type":"order","data":{"statuses":[]}}}"#,
                         #"{"status":"ok","response":{"type":"cancel","data":{"statuses":["success"]}}}"#,
                         #"{"status":"success","response":"ok"}"#,
                         #"{"status":"ok","response":{"type":"order","data":{"statuses":[{"error":"A"},{"error":"B"}]}}}"#,
                         "null", "{}"] {
            XCTAssertThrowsError(try HyperliquidOrderAcknowledgement.decode(Data(response.utf8),
                for: HyperliquidOrderTestSupport.order()))
        }
        XCTAssertThrowsError(try HyperliquidOrderAcknowledgement.decode(Data(repeating: 32, count: 65_537),
            for: HyperliquidOrderTestSupport.order()))
    }

    private func fill(size: String = "3.125", price: String = "230.9", oid: String = "77747314") -> String {
        "{\"filled\":{\"totalSz\":\"\(size)\",\"avgPx\":\"\(price)\",\"oid\":\(oid)}}"
    }

    private func decode(status: String, order: HyperliquidOrderIntent? = nil) throws -> HyperliquidOrderAcknowledgement {
        let response = "{\"status\":\"ok\",\"response\":{\"type\":\"order\",\"data\":{\"statuses\":[\(status)]}}}"
        return try .decode(Data(response.utf8), for: order ?? HyperliquidOrderTestSupport.order())
    }
}
