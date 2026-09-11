import XCTest
import SwiftUI
@testable import BSmart

@MainActor
final class LiveMarketOrderLayoutTests: XCTestCase {
    func testEnglishCompactOpening() async throws {
        try await render(language: .english, scheme: .dark, width: 320, size: .large, reduction: false)
    }

    func testEnglishCompactReductionReview() async throws {
        try await render(language: .english, scheme: .dark, width: 320, size: .large, reduction: true)
    }

    func testChineseLightReductionReview() async throws {
        try await render(language: .simplifiedChinese, scheme: .light, width: 393, size: .large, reduction: true)
    }

    func testChineseLargeTextReductionReview() async throws {
        try await render(language: .simplifiedChinese, scheme: .dark, width: 393, size: .accessibility1, reduction: true)
    }

    func testEnglishPartialReductionReview() async throws {
        try await render(language: .english, scheme: .light, width: 320, size: .large, reduction: true, position: "-4")
    }

    private func render(language: AppLanguage, scheme: ColorScheme, width: CGFloat,
                        size: DynamicTypeSize, reduction: Bool, position: String = "-0.5") async throws {
        let original = BSmartLocalization.language
        BSmartLocalization.configure(language)
        defer { BSmartLocalization.configure(original) }
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let reader = OrderStoreReader()
        await reader.setPosition(position)
        let store = try HyperliquidMarketOrderStore(service: OrderStoreAccount(clock: context.clock),
            journal: context.journal(), reader: reader, clock: { context.clock.now },
            continuousClock: { context.clock.instant }, enabled: { true })
        if reduction {
            await store.reviewReduction(percent: 100, slippageBPS: 50, wallet: HyperliquidTradingFixture.wallet,
                                        dex: "xyz", coin: HyperliquidTradingFixture.coin)
            XCTAssertNotNil(store.preview)
        } else {
            await store.loadEntry(wallet: HyperliquidTradingFixture.wallet, dex: "xyz", coin: HyperliquidTradingFixture.coin)
            XCTAssertNotNil(store.entryAccount)
        }
        let content = LiveMarketOrderView(wallet: HyperliquidTradingFixture.wallet,
            coin: HyperliquidTradingFixture.coin, dex: "xyz", initialSide: .buy, initialAmount: "100",
            store: store, enabled: true, initialReduction: reduction)
            .padding(.horizontal, 16).frame(width: width, height: 760)
            .foregroundStyle(BSmartColor.primaryText).background(BSmartColor.ink)
            .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
            .environment(\.scenePhase, .active)
        let host = UIHostingController(rootView: content)
        host.safeAreaRegions = []
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.rootViewController = host; window.frame = CGRect(x: 0, y: 0, width: width, height: 760)
        host.view.frame = window.bounds; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil; store.invalidate() }
        window.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(host.view.bounds.width, width, accuracy: 1)
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Live order \(reduction ? "reduction" : "opening") \(language.rawValue) \(Int(width)) \(size)"
        attachment.lifetime = .keepAlways; add(attachment)
        let records = try await context.journal().orderRecords(wallet: HyperliquidTradingFixture.wallet)
        XCTAssertTrue(records.isEmpty, "Rendering/review must not reserve, sign or submit an order")
    }
}
