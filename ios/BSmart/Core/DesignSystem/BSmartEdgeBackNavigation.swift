import UIKit
import ObjectiveC

enum BSmartEdgeBackPolicy {
    static func permits(startX: CGFloat, velocity: CGPoint, depth: Int,
                        transitioning: Bool, presenting: Bool, enabled: Bool) -> Bool {
        enabled && depth > 1 && !transitioning && !presenting
            && startX >= 0 && startX <= 24 && velocity.x > 0
            && velocity.x > abs(velocity.y) * 1.25
    }
}

/// Keep UIKit's interactive transition; only restore its start gate for our custom back button.
@MainActor
final class BSmartEdgeBackNavigation: NSObject, UIGestureRecognizerDelegate {
    private static var associationKey: UInt8 = 0
    private weak var navigation: UINavigationController?
    private weak var enabledPage: UIViewController?
    private weak var originalDelegate: (any UIGestureRecognizerDelegate)?
    private var touchStartX: CGFloat?

    static func enable(on navigation: UINavigationController, allowsBack: Bool = true) {
        guard let gesture = navigation.interactivePopGestureRecognizer else { return }
        if #available(iOS 26.0, *) {
            navigation.interactiveContentPopGestureRecognizer?.isEnabled = false
        }
        let bridge: BSmartEdgeBackNavigation
        if let existing = objc_getAssociatedObject(navigation, &associationKey) as? BSmartEdgeBackNavigation {
            bridge = existing
        } else {
            bridge = BSmartEdgeBackNavigation()
            bridge.navigation = navigation
            objc_setAssociatedObject(navigation, &associationKey, bridge, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        if gesture.delegate !== bridge { bridge.originalDelegate = gesture.delegate }
        bridge.enabledPage = allowsBack ? navigation.topViewController : nil
        gesture.delegate = bridge
        gesture.isEnabled = allowsBack && navigation.viewControllers.count > 1
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigation, let pan = gestureRecognizer as? UIPanGestureRecognizer,
              let touchStartX, pan.numberOfTouches <= 1 else { return false }
        return BSmartEdgeBackPolicy.permits(
            startX: touchStartX,
            velocity: pan.velocity(in: navigation.view),
            depth: navigation.viewControllers.count,
            transitioning: navigation.transitionCoordinator != nil,
            presenting: navigation.presentedViewController != nil,
            enabled: enabledPage === navigation.topViewController
                && navigation.topViewController?.isModalInPresentation != true
        )
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive event: UIEvent) -> Bool {
        guard let navigation else { return false }
        return enabledPage === navigation.topViewController && navigation.viewControllers.count > 1
            && navigation.transitionCoordinator == nil && navigation.presentedViewController == nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let navigation else { return false }
        let x = touch.location(in: navigation.view).x
        let accepted = x >= 0 && x <= 24
        touchStartX = accepted ? x : nil
        return accepted
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Forward public arbitration only; UIKit's hidden-back private gates would disable the gesture again.
        originalDelegate?.gestureRecognizer?(gestureRecognizer, shouldRecognizeSimultaneouslyWith: other) ?? false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
        originalDelegate?.gestureRecognizer?(gestureRecognizer, shouldRequireFailureOf: other) ?? false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        originalDelegate?.gestureRecognizer?(gestureRecognizer, shouldBeRequiredToFailBy: other) ?? false
    }
}
