import SwiftUI
import UIKit

/// Only horizontal drags belong to the chart. Vertical drags remain with the page.
struct BSmartChartGestures: UIViewRepresentable {
    let inspect: (CGFloat) -> Void
    let pan: (CGFloat) -> Void
    let zoom: (CGFloat, CGFloat) -> Void
    let reset: () -> Void

    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.actions = self
        return view
    }

    func updateUIView(_ uiView: Surface, context: Context) { uiView.actions = self }

    final class Surface: UIView, UIGestureRecognizerDelegate {
        var actions: BSmartChartGestures?
        private var inspecting = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
            pan.maximumNumberOfTouches = 1
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched))
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held))
            hold.minimumPressDuration = 0.25
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
            doubleTap.numberOfTapsRequired = 2
            tap.require(toFail: doubleTap)
            pan.require(toFail: hold)
            for gesture in [pan, pinch, hold, tap, doubleTap] {
                gesture.delegate = self
                addGestureRecognizer(gesture)
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if let pan = gestureRecognizer as? UIPanGestureRecognizer {
                let velocity = pan.velocity(in: self)
                return abs(velocity.x) > abs(velocity.y)
            }
            return true
        }

        private func fraction(_ gesture: UIGestureRecognizer) -> CGFloat {
            min(max(gesture.location(in: self).x / max(bounds.width, 1), 0), 1)
        }

        @objc private func panned(_ gesture: UIPanGestureRecognizer) {
            guard !inspecting, gesture.state == .changed else { return }
            actions?.pan(gesture.translation(in: self).x / max(bounds.width, 1))
            gesture.setTranslation(.zero, in: self)
        }

        @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .changed else { return }
            actions?.zoom(gesture.scale, fraction(gesture))
            gesture.scale = 1
        }

        @objc private func held(_ gesture: UILongPressGestureRecognizer) {
            inspecting = gesture.state == .began || gesture.state == .changed
            if inspecting { actions?.inspect(fraction(gesture)) }
        }

        @objc private func tapped(_ gesture: UITapGestureRecognizer) { actions?.inspect(fraction(gesture)) }
        @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) { actions?.reset() }
    }
}
