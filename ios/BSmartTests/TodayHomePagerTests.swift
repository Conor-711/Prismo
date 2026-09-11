import XCTest
import UIKit
@testable import BSmart

final class TodayHomePagerTests: XCTestCase {
    private typealias TodayHomeScrollState = BSmartCollapsingScrollState<TodayHomeSection>
    func testStableSceneOrder() {
        XCTAssertEqual(TodayHomeSection.allCases, [.portfolio, .market, .investors])
    }

    func testNewSceneKeepsCollapsedHeaderAndReadSceneKeepsItsDepth() {
        XCTAssertEqual(TodayHomeScrollState.destinationOffset(saved: 0, collapsedHeight: 500), 500)
        XCTAssertEqual(TodayHomeScrollState.destinationOffset(saved: 820, collapsedHeight: 500), 820)
        XCTAssertEqual(TodayHomeScrollState.destinationOffset(saved: -20, collapsedHeight: 0), 0)
    }

    @MainActor
    func testIndependentOffsetsAndSharedHeader() {
        let state = TodayHomeScrollState(selection: .portfolio)
        state.headerHeight = 500
        let portfolio = scrollView()
        let market = scrollView()
        state.register(portfolio, section: .portfolio)
        portfolio.contentOffset.y = 780
        state.observe(portfolio, section: .portfolio)
        XCTAssertEqual(state.collapsedHeight, 500)
        state.register(market, section: .market)
        state.select(.market)
        XCTAssertEqual(market.contentOffset.y, 500)
        market.contentOffset.y = 960
        state.observe(market, section: .market)
        state.select(.portfolio)
        XCTAssertEqual(portfolio.contentOffset.y, 780)
        portfolio.contentOffset.y = 0
        state.observe(portfolio, section: .portfolio)
        XCTAssertEqual(state.collapsedHeight, 0)
        state.select(.market)
        XCTAssertEqual(market.contentOffset.y, 960)
    }

    @MainActor
    func testInactivePageCannotMoveHeader() {
        let state = TodayHomeScrollState(selection: .portfolio)
        state.headerHeight = 500
        let background = scrollView()
        background.contentOffset.y = 300
        state.observe(background, section: .market)
        XCTAssertEqual(state.collapsedHeight, 0)
    }

    @MainActor
    func testHeaderResizeReconcilesCollapseWithoutResettingPageDepth() {
        let state = TodayHomeScrollState(selection: .portfolio)
        state.headerHeight = 500
        let view = scrollView()
        view.contentOffset.y = 750
        state.observe(view, section: .portfolio)
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
