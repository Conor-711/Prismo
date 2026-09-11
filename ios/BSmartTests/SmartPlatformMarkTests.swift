import UIKit
import XCTest
@testable import BSmart

final class SmartPlatformMarkTests: XCTestCase {
    @MainActor
    func testRedditLogoIsBundledAndRetainsItsOriginalColors() throws {
        let image = try XCTUnwrap(UIImage(named: "PlatformReddit"))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertEqual(image.size.width, image.size.height)
        XCTAssertEqual(image.renderingMode, .alwaysOriginal)
    }
}
