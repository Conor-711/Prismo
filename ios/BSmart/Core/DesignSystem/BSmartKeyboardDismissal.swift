import SwiftUI
import UIKit

/// One passive recognizer per scene window also covers sheets and pushed pages.
struct BSmartKeyboardDismissal: UIViewRepresentable {
    func makeUIView(context: Context) -> Surface { Surface() }
    func updateUIView(_ uiView: Surface, context: Context) {}
    static func dismantleUIView(_ uiView: Surface, coordinator: ()) { uiView.detach() }

    final class Surface: UIView, UIGestureRecognizerDelegate {
        private weak var attachedWindow: UIWindow?
        private weak var input: UIView?
        private weak var tappedInput: UIView?
        private lazy var tap: UITapGestureRecognizer = {
            let value = UITapGestureRecognizer(target: self, action: #selector(dismissInput))
            value.name = "bsmart.dismiss-keyboard"
            value.cancelsTouchesInView = false
            value.delaysTouchesBegan = false
            value.delaysTouchesEnded = false
            value.delegate = self
            return value
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            for name in [UITextField.textDidBeginEditingNotification, UITextView.textDidBeginEditingNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(editingBegan), name: name, object: nil)
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        deinit { NotificationCenter.default.removeObserver(self) }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard attachedWindow !== window else { return }
            detach()
            attachedWindow = window
            window?.addGestureRecognizer(tap)
        }

        func detach() {
            attachedWindow?.removeGestureRecognizer(tap)
            attachedWindow = nil
            input = nil
            tappedInput = nil
        }

        @objc private func editingBegan(_ notification: Notification) {
            guard let view = notification.object as? UIView,
                  let window = attachedWindow, view.window === window else { return }
            input = view
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let input, input.isFirstResponder, let window = attachedWindow,
                  input.window === window, Self.isOutsideInput(touch.view),
                  !BSmartKeyboardInputRegion.contains(touch.location(in: window), in: window, input: input)
            else { return false }
            tappedInput = input
            return true
        }

        static func isOutsideInput(_ touchedView: UIView?) -> Bool {
            var current = touchedView
            while let view = current {
                // Keep cursor selection, paste menus, clear buttons and switching fields native.
                if view is UITextInput || view is UISearchBar { return false }
                current = view.superview
            }
            return touchedView != nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        @objc private func dismissInput() {
            // A button may already have focused another field; never resign the new responder.
            if let tappedInput, tappedInput.isFirstResponder { tappedInput.resignFirstResponder() }
            tappedInput = nil
        }
    }
}

/// Includes accessory buttons in a SwiftUI search field's editing area.
struct BSmartKeyboardInputRegion: UIViewRepresentable {
    private static let regions = NSHashTable<UIView>.weakObjects()

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        Self.regions.add(view)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}

    static func contains(_ point: CGPoint, in window: UIWindow, input: UIView) -> Bool {
        let inputFrame = input.convert(input.bounds, to: window)
        return regions.allObjects.contains { region in
            guard region.window === window, !region.isHidden else { return false }
            let frame = region.convert(region.bounds, to: window)
            return frame.contains(point) && frame.contains(CGPoint(x: inputFrame.midX, y: inputFrame.midY))
        }
    }
}
