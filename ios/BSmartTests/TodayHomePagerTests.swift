import XCTest
import UIKit
import SwiftUI
@testable import BSmart

final class TodayHomePagerTests: XCTestCase {
    private typealias TodayHomeScrollState = BSmartCollapsingScrollState<TodayHomeSection>

    @MainActor
    func testScrollTicksDoNotRebuildHeaderOrPageContent() async throws {
        let builds = PagerBuildCounts()
        let pager = BSmartCollapsingPager(selection: .constant(TodayHomeSection.activity),
            sections: TodayHomeSection.allCases, pageIdentifier: { $0.rawValue },
            header: { _ in builds.header() }, tabs: { Text("Tabs").frame(height: 52) },
            content: { _ in builds.page() }, refresh: {})
        let host = UIHostingController(rootView: pager)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        func probe(in view: UIView) -> BSmartCollapsingScrollProbe<TodayHomeSection>.ProbeView? {
            if let match = view as? BSmartCollapsingScrollProbe<TodayHomeSection>.ProbeView,
               match.section == .activity { return match }
            return view.subviews.lazy.compactMap { probe(in: $0) }.first
        }
        let state = try XCTUnwrap(probe(in: host.view)).state
        let initialHeaders = builds.headers, initialPages = builds.pages
        for tick in 1...30 {
            state.scrollHeader(to: CGFloat(tick * 5))
            try await Task.sleep(for: .milliseconds(18))
        }
        XCTAssertEqual(state.collapsedHeight, 150, accuracy: 1)
        XCTAssertEqual(builds.headers, initialHeaders, "Scrolling must not reconstruct the chart header")
        XCTAssertEqual(builds.pages, initialPages, "Scrolling must not re-run page aggregation")
    }
    func testStableSceneOrder() {
        XCTAssertEqual(TodayHomeSection.allCases, [.activity, .assets])
    }

    func testNewSceneKeepsCollapsedHeaderAndReadSceneKeepsItsDepth() {
        XCTAssertEqual(TodayHomeScrollState.destinationOffset(saved: 0, collapsedHeight: 500), 500)
        XCTAssertEqual(TodayHomeScrollState.destinationOffset(saved: 820, collapsedHeight: 500), 820)
        XCTAssertEqual(TodayHomeScrollState.destinationOffset(saved: -20, collapsedHeight: 0), 0)
    }

    @MainActor
    func testIndependentOffsetsAndSharedHeader() {
        let state = TodayHomeScrollState(selection: .activity)
        state.headerHeight = 500
        let activity = scrollView()
        let assets = scrollView()
        state.register(activity, section: .activity)
        activity.contentOffset.y = 780
        state.observe(activity, section: .activity)
        XCTAssertEqual(state.collapsedHeight, 500)
        state.register(assets, section: .assets)
        state.select(.assets)
        XCTAssertEqual(assets.contentOffset.y, 500)
        assets.contentOffset.y = 960
        state.observe(assets, section: .assets)
        state.select(.activity)
        XCTAssertEqual(activity.contentOffset.y, 780)
        activity.contentOffset.y = 0
        state.observe(activity, section: .activity)
        XCTAssertEqual(state.collapsedHeight, 0)
        state.select(.assets)
        XCTAssertEqual(assets.contentOffset.y, 960)
    }

    @MainActor
    func testInactivePageCannotMoveHeader() {
        let state = TodayHomeScrollState(selection: .activity)
        state.headerHeight = 500
        let background = scrollView()
        background.contentOffset.y = 300
        state.observe(background, section: .assets)
        XCTAssertEqual(state.collapsedHeight, 0)
    }

    @MainActor
    func testHeaderResizeReconcilesCollapseWithoutResettingPageDepth() {
        let state = TodayHomeScrollState(selection: .activity)
        state.headerHeight = 500
        let view = scrollView()
        view.contentOffset.y = 750
        state.observe(view, section: .activity)
        state.headerHeight = 900
        XCTAssertEqual(state.collapsedHeight, 750)
        state.headerHeight = 400
        XCTAssertEqual(state.collapsedHeight, 400)
        XCTAssertEqual(state.currentOffset, 750)
    }

    @MainActor
    private func scrollView() -> UIScrollView {
        let view = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        view.contentSize = CGSize(width: 390, height: 2400)
        return view
    }
}

@MainActor
private final class PagerBuildCounts {
    var headers = 0
    var pages = 0
    func header() -> some View {
        headers += 1
        return Color.clear.frame(height: 300)
    }
    func page() -> some View {
        pages += 1
        return Color.clear.frame(height: 1600)
    }
}
