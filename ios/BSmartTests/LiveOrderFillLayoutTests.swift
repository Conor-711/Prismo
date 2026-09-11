import XCTest
import SwiftUI
@testable import BSmart

@MainActor
final class LiveOrderFillLayoutTests: XCTestCase {
    typealias F = OrderFillFixture

    func testEnglishCompactCompleteFills() async throws {
        try await render(language: .english, scheme: .dark, width: 320, size: .large,
                         summary: .init(record: F.record(), fills: [F.fill(), F.fill(["tid": 2, "sz": "1.5", "px": "220"]) ]))
    }

    func testChineseLightPartialFills() async throws {
        try await render(language: .simplifiedChinese, scheme: .light, width: 393, size: .large,
                         summary: .init(record: F.record(), fills: [F.fill()]))
    }

    func testChineseAccessibilityWithExactSmallRebate() async throws {
        try await render(language: .simplifiedChinese, scheme: .dark, width: 393, size: .accessibility1,
                         summary: .init(record: F.record(size: "1"), fills: [F.fill(["fee": "-0.000000000000000001"]) ]))
    }

    func testMissingFeesAreNotPresentedAsZero() async throws {
        try await render(language: .english, scheme: .dark, width: 320, size: .large, summary: nil)
    }

    private func render(language: AppLanguage, scheme: ColorScheme, width: CGFloat,
                        size: DynamicTypeSize, summary: HyperliquidFillSummary?) async throws {
        let original = BSmartLocalization.language
        BSmartLocalization.configure(language)
        defer { BSmartLocalization.configure(original) }
        let content = ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("xyz:NVDA").font(.headline)
                LiveOrderFillView(summary: summary, initiallyExpanded: true)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(width: width, height: 900)
            .foregroundStyle(BSmartColor.primaryText).background(BSmartColor.ink).tint(BSmartColor.brand)
            .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
        let host = UIHostingController(rootView: content)
        host.safeAreaRegions = []
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.rootViewController = host; window.frame = CGRect(x: 0, y: 0, width: width, height: 900)
        host.view.frame = window.bounds; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        window.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(host.view.bounds.width, width, accuracy: 1)
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Fills \(language.rawValue) \(Int(width)) \(size) \(scheme)"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
