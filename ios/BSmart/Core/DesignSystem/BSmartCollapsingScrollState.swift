import SwiftUI
import UIKit

final class BSmartCollapsingScrollState<Section: Hashable>: ObservableObject {
    @Published private(set) var collapsedHeight: CGFloat = 0
    private(set) var selection: Section
    var headerHeight: CGFloat = 0 {
        didSet { collapsedHeight = min(currentOffset, max(0, headerHeight)) }
    }
    private var scrollViews: [Section: WeakScrollView] = [:]
    private var offsets: [Section: CGFloat] = [:]
    var currentOffset: CGFloat { offsets[selection] ?? 0 }

    init(selection: Section) { self.selection = selection }

    func scrollHeader(to offset: CGFloat, animated: Bool = false) {
        guard let view = scrollViews[selection]?.value else { return }
        setOffset(max(0, offset), in: view, animated: animated)
        if !animated { observe(view, section: selection) }
    }

    static func destinationOffset(saved: CGFloat, collapsedHeight: CGFloat) -> CGFloat {
        max(0, saved, collapsedHeight)
    }

    func register(_ view: UIScrollView, section: Section) {
        scrollViews[section] = WeakScrollView(view)
        let target = Self.destinationOffset(saved: offsets[section] ?? 0, collapsedHeight: collapsedHeight)
        setOffset(target, in: view)
    }

    func select(_ section: Section) {
        selection = section
        let target = Self.destinationOffset(saved: offsets[section] ?? 0, collapsedHeight: collapsedHeight)
        offsets[section] = target
        if let view = scrollViews[section]?.value { setOffset(target, in: view) }
        collapsedHeight = min(target, headerHeight)
    }

    func observe(_ view: UIScrollView, section: Section) {
        let offset = max(0, view.contentOffset.y + view.adjustedContentInset.top)
        offsets[section] = offset
        guard section == selection else { return }
        let collapse = min(offset, headerHeight)
        if abs(collapse - collapsedHeight) > 0.5 { collapsedHeight = collapse }
    }

    private func setOffset(_ target: CGFloat, in view: UIScrollView, animated: Bool = false) {
        let limit = max(0, view.contentSize.height - view.bounds.height
                        + view.adjustedContentInset.top + view.adjustedContentInset.bottom)
        guard limit > 0 else { return }
        let y = min(target, limit) - view.adjustedContentInset.top
        if abs(view.contentOffset.y - y) > 0.5 {
            view.setContentOffset(CGPoint(x: view.contentOffset.x, y: y), animated: animated)
        }
    }

    private final class WeakScrollView {
        weak var value: UIScrollView?
        init(_ value: UIScrollView) { self.value = value }
    }
}

// Observe only each page's vertical ScrollView; never replace its delegate or pan gesture.
struct BSmartCollapsingScrollProbe<Section: Hashable>: UIViewRepresentable {
    let section: Section
    let state: BSmartCollapsingScrollState<Section>

    func makeUIView(context: Context) -> ProbeView { ProbeView(section: section, state: state) }
    func updateUIView(_ view: ProbeView, context: Context) { view.connectWhenReady() }

    final class ProbeView: UIView {
        let section: Section
        let state: BSmartCollapsingScrollState<Section>
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var sizeObservation: NSKeyValueObservation?

        init(section: Section, state: BSmartCollapsingScrollState<Section>) {
            self.section = section
            self.state = state
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            connectWhenReady()
        }

        func connectWhenReady() {
            DispatchQueue.main.async { [weak self] in self?.connect() }
        }

        private func connect() {
            guard window != nil else { return }
            var ancestor = superview
            while let candidate = ancestor, !(candidate is UIScrollView) { ancestor = candidate.superview }
            guard let view = ancestor as? UIScrollView, view !== scrollView else { return }
            observation?.invalidate()
            sizeObservation?.invalidate()
            scrollView = view
            state.register(view, section: section)
            observation = view.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    guard let self, let view = self.scrollView else { return }
                    self.state.observe(view, section: self.section)
                }
            }
            sizeObservation = view.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    guard let self, let view = self.scrollView else { return }
                    self.state.register(view, section: self.section)
                }
            }
        }
    }
}
