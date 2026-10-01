import XCTest
import UIKit
@testable import BSmart

@MainActor
final class BSmartDetailVisibilityTests: XCTestCase {
    func testEdgeBackRejectsVerticalCentralRootAndUnsafeTransitions() {
        func permits(_ x: CGFloat = 2, _ velocity: CGPoint = CGPoint(x: 300, y: 20),
                     depth: Int = 2, transitioning: Bool = false, presenting: Bool = false,
                     enabled: Bool = true) -> Bool {
            BSmartEdgeBackPolicy.permits(startX: x, velocity: velocity, depth: depth,
                                        transitioning: transitioning, presenting: presenting, enabled: enabled)
        }
        XCTAssertTrue(permits())
        XCTAssertFalse(permits(80))
        XCTAssertFalse(permits(2, CGPoint(x: 60, y: 200)))
        XCTAssertFalse(permits(2, CGPoint(x: -300, y: 0)))
        XCTAssertFalse(permits(depth: 1))
        XCTAssertFalse(permits(transitioning: true))
        XCTAssertFalse(permits(presenting: true))
        XCTAssertFalse(permits(enabled: false))
    }

    func testEdgeBridgeIsRetainedPerNavigationStackAndNeverEnablesRootPop() {
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.loadViewIfNeeded()
        BSmartEdgeBackNavigation.enable(on: navigation)
        XCTAssertFalse(navigation.interactivePopGestureRecognizer!.isEnabled)
        navigation.pushViewController(UIViewController(), animated: false)
        BSmartEdgeBackNavigation.enable(on: navigation)
        let delegate = navigation.interactivePopGestureRecognizer!.delegate
        XCTAssertTrue(delegate is BSmartEdgeBackNavigation)
        XCTAssertTrue(navigation.interactivePopGestureRecognizer!.isEnabled)
        BSmartEdgeBackNavigation.enable(on: navigation)
        XCTAssertTrue(delegate === navigation.interactivePopGestureRecognizer!.delegate)
    }

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

    func testRetainedParentCannotReenableBackOnProtectedChildPage() {
        let router = AppRouter()
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        let parentPage = UIViewController()
        let parent = BSmartDetailVisibilityController(router: router, token: UUID())
        parentPage.addChild(parent)
        parent.didMove(toParent: parentPage)
        navigation.pushViewController(parentPage, animated: false)
        parent.restoreEdgeBackForCurrentPage()
        XCTAssertTrue(navigation.interactivePopGestureRecognizer!.isEnabled)

        let childPage = UIViewController()
        let child = BSmartDetailVisibilityController(router: router, token: UUID(), allowsBack: false)
        childPage.addChild(child)
        child.didMove(toParent: childPage)
        navigation.pushViewController(childPage, animated: false)
        child.restoreEdgeBackForCurrentPage()
        XCTAssertFalse(navigation.interactivePopGestureRecognizer!.isEnabled)
        parent.restoreEdgeBackForCurrentPage()
        XCTAssertFalse(navigation.interactivePopGestureRecognizer!.isEnabled)
        child.allowsBack = true
        child.restoreEdgeBackForCurrentPage()
        XCTAssertTrue(navigation.interactivePopGestureRecognizer!.isEnabled)
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
