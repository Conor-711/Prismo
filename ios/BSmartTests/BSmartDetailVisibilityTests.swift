import XCTest
@testable import BSmart

@MainActor
final class BSmartDetailVisibilityTests: XCTestCase {
    func testDetailKeepsNavigationHiddenUntilControllerActuallyDisappears() {
        let router = AppRouter()
        let controller = BSmartDetailVisibilityController(router: router, token: UUID())
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
        XCTAssertTrue(router.isTabBarHidden)
        controller.beginAppearanceTransition(false, animated: false)
        XCTAssertTrue(router.isTabBarHidden)
        controller.endAppearanceTransition()
        XCTAssertFalse(router.isTabBarHidden)
    }

    func testNestedDetailAndReappearanceKeepTheirOwnVisibility() {
        let router = AppRouter()
        let parent = BSmartDetailVisibilityController(router: router, token: UUID())
        let child = BSmartDetailVisibilityController(router: router, token: UUID())
        transition(parent, appears: true)
        transition(child, appears: true)
        transition(parent, appears: false)
        XCTAssertTrue(router.isTabBarHidden)
        router.setTabBarHidden(false, token: child.token)
        XCTAssertFalse(router.isTabBarHidden)
        transition(child, appears: false)
        transition(child, appears: true)
        XCTAssertTrue(router.isTabBarHidden)
        transition(parent, appears: true)
        transition(child, appears: false)
        XCTAssertTrue(router.isTabBarHidden)
        transition(parent, appears: false)
        XCTAssertFalse(router.isTabBarHidden)
    }

    private func transition(_ controller: BSmartDetailVisibilityController, appears: Bool) {
        controller.beginAppearanceTransition(appears, animated: false)
        controller.endAppearanceTransition()
    }
}
