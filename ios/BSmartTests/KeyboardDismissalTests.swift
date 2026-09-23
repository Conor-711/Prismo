import XCTest
import UIKit
@testable import BSmart

@MainActor
final class KeyboardDismissalTests: XCTestCase {
    func testInputDescendantsNeverDismissEditing() {
        let field = UITextField()
        let clearButton = UIButton()
        field.addSubview(clearButton)
        XCTAssertFalse(BSmartKeyboardDismissal.Surface.isOutsideInput(field))
        XCTAssertFalse(BSmartKeyboardDismissal.Surface.isOutsideInput(clearButton))
        field.isSecureTextEntry = true
        XCTAssertFalse(BSmartKeyboardDismissal.Surface.isOutsideInput(field))
        XCTAssertFalse(BSmartKeyboardDismissal.Surface.isOutsideInput(UITextView()))
        XCTAssertFalse(BSmartKeyboardDismissal.Surface.isOutsideInput(UISearchBar()))
        XCTAssertTrue(BSmartKeyboardDismissal.Surface.isOutsideInput(UIButton()))
        XCTAssertTrue(BSmartKeyboardDismissal.Surface.isOutsideInput(UIControl()))
        XCTAssertTrue(BSmartKeyboardDismissal.Surface.isOutsideInput(UIView()))
        XCTAssertFalse(BSmartKeyboardDismissal.Surface.isOutsideInput(nil))
    }

    func testWindowInstallsOnePassiveRecognizerAndDetaches() {
        let window = UIWindow()
        let surface = BSmartKeyboardDismissal.Surface()
        window.addSubview(surface)
        surface.didMoveToWindow()
        let gestures = (window.gestureRecognizers ?? []).filter { $0.name == "bsmart.dismiss-keyboard" }
        XCTAssertEqual(gestures.count, 1)
        XCTAssertEqual(gestures.first?.cancelsTouchesInView, false)
        XCTAssertEqual(gestures.first?.delaysTouchesBegan, false)
        XCTAssertEqual(gestures.first?.delaysTouchesEnded, false)
        surface.removeFromSuperview()
        XCTAssertFalse((window.gestureRecognizers ?? []).contains { $0.name == "bsmart.dismiss-keyboard" })
    }
}
