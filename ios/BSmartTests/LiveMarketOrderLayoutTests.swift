import XCTest
import SwiftUI
@testable import BSmart

@MainActor
final class LiveMarketOrderLayoutTests: XCTestCase {
    func testEnglishCompactOpening() async throws {
        try await render(language: .english, scheme: .dark, width: 320, size: .large, reduction: false)
    }

    func testChineseLightOpening() async throws {
        try await render(language: .simplifiedChinese, scheme: .light, width: 393, size: .large, reduction: false)
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
        let service = OrderStoreAccount(clock: context.clock)
        await reader.setPosition(position)
        let store = try HyperliquidMarketOrderStore(service: service,
            journal: context.journal(), reader: reader, clock: { context.clock.now },
            continuousClock: { context.clock.instant }, enabled: { true })
        let balances = HyperCoreBalanceStore(service: service, provider: LayoutBalanceProvider())
        await store.loadEntry(wallet: HyperliquidTradingFixture.wallet, dex: "xyz", coin: HyperliquidTradingFixture.coin)
        XCTAssertNotNil(store.entryAccount)
        let trading = HyperliquidTradingStore(client: DebugTradingMarketClient())
        let market = try await DebugTradingMarketClient().fetchMarkets(dex: .init(name: "xyz", displayName: "XYZ"))[0]
        let content = LiveOrderComposer(wallet: HyperliquidTradingFixture.wallet, coin: HyperliquidTradingFixture.coin,
                    dex: "xyz", side: .buy, initialNotional: "100", market: market, enabled: true,
                    store: store, balances: balances, reducing: reduction).environmentObject(trading)
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

private struct LayoutBalanceProvider: HyperCoreBalanceProviding {
    func snapshot(wallet: DeviceWalletSummary) async throws -> HyperCoreBalanceSnapshot {
        let now = Date()
        return try .init(accountID: wallet.accountID, owner: wallet.address, mode: .unifiedAccount,
                         usdc: .init("100"), held: .init("0"), perps: nil, requestedAt: now, checkedAt: now)
    }
}
