import UIKit
import XCTest
@testable import BSmart

final class TickerLogoTests: XCTestCase {
    @MainActor
    func testEveryRegisteredLogoLoadsFromCompiledAssetCatalog() {
        XCTAssertGreaterThan(TickerLogoRegistry.symbols.count, 480)
        for symbol in TickerLogoRegistry.symbols.sorted() {
            let image = UIImage(named: "Ticker_\(symbol)")
            XCTAssertNotNil(image, "Missing compiled logo: \(symbol)")
            XCTAssertGreaterThan(image?.size.width ?? 0, 0, symbol)
            XCTAssertGreaterThan(image?.size.height ?? 0, 0, symbol)
        }
    }

    func testSpecialMarketCodesHaveExplicitAssets() {
        for symbol in ["SKHX", "SKHY", "SMSN", "DRAM", "SPCX", "SNDK", "MU",
                       "DGXX", "MRLN", "UNITREE", "LYTE", "NCLD", "YMTC", "SHEIN"] {
            XCTAssertTrue(TickerLogoRegistry.symbols.contains(symbol), symbol)
        }
        XCTAssertFalse(TickerLogoRegistry.symbols.contains("MARKET"))
    }
}
