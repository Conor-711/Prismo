import XCTest
@testable import BSmart

final class HyperliquidExecutionMarketTests: XCTestCase {
    private let dexs = #"[null,{"name":"first"},null,{"name":"xyz"}]"#
    private let metadata = #"{"collateralToken":0,"universe":[{"name":"xyz:OLD","szDecimals":3,"maxLeverage":10,"isDelisted":true},{"name":"xyz:NVDA","szDecimals":3,"maxLeverage":20,"onlyIsolated":true}]}"#

    func testPreservesRawDexAndAssetSlots() throws {
        let result = try resolve(dexs, metadata)
        XCTAssertEqual(result.asset, 130001)
        XCTAssertEqual(result.coin, "xyz:NVDA")
        XCTAssertEqual(result.dex, "xyz")
        XCTAssertEqual(result.sizeDecimals, 3)
        XCTAssertEqual(result.collateralToken, 0)
        XCTAssertEqual(result.maximumLeverage, 20)
        XCTAssertTrue(result.isolatedOnly)
    }

    func testNativeIndexAndDifferentCollateralArePreserved() throws {
        let native = metadata.replacingOccurrences(of: "xyz:", with: "")
            .replacingOccurrences(of: "\"collateralToken\":0", with: "\"collateralToken\":7")
        let result = try resolve(dexs, native, dex: "", coin: "NVDA")
        XCTAssertEqual(result.asset, 1)
        XCTAssertEqual(result.collateralToken, 7) // Not automatically spendable with deposited USDC.
    }

    func testNoTickerAliasOrDelistedMarketResolution() {
        for coin in ["NVDA", "other:NVDA", "xyz:OLD", "xyz:nvda", "xyz:MISSING"] {
            XCTAssertThrowsError(try resolve(dexs, metadata, coin: coin), coin)
        }
        XCTAssertThrowsError(try resolve(dexs, metadata, dex: "missing"))
        XCTAssertThrowsError(try resolve(dexs, metadata, dex: ""))
    }

    func testMalformedDexCatalogIsRejected() {
        for value in ["[]", #"[{"name":"xyz"}]"#, #"[null,{"name":"xyz"},{"name":"xyz"}]"#,
                      #"[null,{"name":""}]"#, #"[null,{"name":"xyz:bad"}]"#, #"[null,{}]"#] {
            XCTAssertThrowsError(try resolve(value, metadata), value)
        }
    }

    func testOversizedMetadataIsRejectedBeforeDecoding() {
        XCTAssertThrowsError(try HyperliquidExecutionMarket.resolve(perpDexs: Data(repeating: 32, count: 262_145),
            meta: Data(metadata.utf8), dex: "xyz", coin: "xyz:NVDA"))
        XCTAssertThrowsError(try HyperliquidExecutionMarket.resolve(perpDexs: Data(dexs.utf8),
            meta: Data(repeating: 32, count: 1_048_577), dex: "xyz", coin: "xyz:NVDA"))
    }

    func testInvalidMarketMetadataFailsClosed() {
        for value in [metadata.replacingOccurrences(of: "\"collateralToken\":0,", with: ""),
                      metadata.replacingOccurrences(of: "\"collateralToken\":0", with: "\"collateralToken\":-1"),
                      metadata.replacingOccurrences(of: "xyz:OLD", with: "xyz:NVDA"),
                      metadata.replacingOccurrences(of: "xyz:OLD", with: "foreign:OLD"),
                      metadata.replacingOccurrences(of: "\"szDecimals\":3", with: "\"szDecimals\":7"),
                      metadata.replacingOccurrences(of: "\"maxLeverage\":20", with: "\"maxLeverage\":0"),
                      metadata.replacingOccurrences(of: "\"szDecimals\":3", with: "\"szDecimals\":true")] {
            XCTAssertThrowsError(try resolve(dexs, value), value)
        }
    }

    func testNewMarginModeIsPreservedWithoutDeprecatedOnlyIsolated() throws {
        for mode in ["noCross", "strictIsolated"] {
            let result = try HyperliquidTradingFixture.market(mode: mode)
            XCTAssertTrue(result.isolatedOnly)
            XCTAssertEqual(result.marginRestriction?.rawValue, mode)
            let data = try HyperliquidTradingFixture.metadata(mode: mode)
            var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var rows = try XCTUnwrap(root["universe"] as? [[String: Any]])
            rows[0]["onlyIsolated"] = false; root["universe"] = rows
            XCTAssertThrowsError(try HyperliquidExecutionMarket.resolve(perpDexs: HyperliquidOrderTestSupport.dexs,
                meta: HyperliquidTradingFixture.data(root), dex: "xyz", coin: HyperliquidTradingFixture.coin))
        }
        XCTAssertThrowsError(try HyperliquidTradingFixture.market(mode: "future-mode"))
        XCTAssertNil(try HyperliquidTradingFixture.market().marginRestriction)
    }

    private func resolve(_ dexs: String, _ meta: String, dex: String = "xyz", coin: String = "xyz:NVDA") throws
        -> HyperliquidExecutionMarket {
        try .resolve(perpDexs: Data(dexs.utf8), meta: Data(meta.utf8), dex: dex, coin: coin)
    }
}
