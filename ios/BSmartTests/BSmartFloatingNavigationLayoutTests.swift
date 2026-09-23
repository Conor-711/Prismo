import XCTest
@testable import BSmart

final class BSmartFloatingNavigationLayoutTests: XCTestCase {
    func testFullHeightViewportIncludesHomeIndicatorAndDockClearance() {
        let viewport = CGRect(x: 0, y: 62, width: 393, height: 790)
        let dock = CGRect(x: 0, y: 743, width: 393, height: 75)
        XCTAssertEqual(BSmartFloatingNavigationLayout.bottomSpacing(viewport: viewport, navigationFrame: dock), 125)
    }

    func testInsetViewportOnlyReservesItsActualOverlap() {
        let viewport = CGRect(x: 0, y: 62, width: 393, height: 756)
        let dock = CGRect(x: 0, y: 743, width: 393, height: 75)
        XCTAssertEqual(BSmartFloatingNavigationLayout.bottomSpacing(viewport: viewport, navigationFrame: dock), 91)
    }

    func testNonOverlappingViewportAndInitialLayout() {
        let viewport = CGRect(x: 0, y: 0, width: 393, height: 600)
        let dock = CGRect(x: 0, y: 743, width: 393, height: 75)
        XCTAssertEqual(BSmartFloatingNavigationLayout.bottomSpacing(viewport: viewport, navigationFrame: dock), 16)
        XCTAssertEqual(BSmartFloatingNavigationLayout.bottomSpacing(viewport: viewport, navigationFrame: .null), 128)
    }
}
