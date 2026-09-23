import XCTest
import SwiftUI
@testable import BSmart

@MainActor
final class HyperCoreBalanceLayoutTests: XCTestCase {
    func testProfileBalanceFitsSmallScreenWithoutTechnicalPanel() async throws {
        try await render(language: .english, scheme: .light, width: 320, size: .large,
                         mode: .unifiedAccount, compact: true)
        try await render(language: .simplifiedChinese, scheme: .dark, width: 320, size: .large,
                         mode: .disabled, compact: true)
    }

    func testProfileUnavailableBalanceStillHasBoundedLayout() async throws {
        try await render(language: .english, scheme: .dark, width: 320, size: .large,
                         mode: nil, compact: true)
    }
    func testCompactEnglishUnifiedBalance() async throws {
        try await render(language: .english, scheme: .dark, width: 320, size: .large, mode: .unifiedAccount)
    }

    func testCompactEnglishSeparateAccountsWithLargeAmounts() async throws {
        try await render(language: .english, scheme: .dark, width: 320, size: .large, mode: .disabled, largeAmount: true)
    }

    func testChineseLightPortfolioMarginAccessibility() async throws {
        try await render(language: .simplifiedChinese, scheme: .light, width: 430, size: .accessibility1, mode: .portfolioMargin)
    }

    func testEnglishAccessibilityExpiredBalance() async throws {
        try await render(language: .english, scheme: .light, width: 320, size: .accessibility1, mode: nil)
    }

    private func render(language: AppLanguage, scheme: ColorScheme, width: CGFloat, size: DynamicTypeSize,
                        mode: HyperCoreAccountMode?, largeAmount: Bool = false, compact: Bool = false) async throws {
        let original = BSmartLocalization.language
        BSmartLocalization.configure(language)
        defer { BSmartLocalization.configure(original) }
        var snapshot = try mode.map { try CoreBalanceFixture.snapshot(mode: $0) }
        if largeAmount, let current = snapshot {
            snapshot = try .init(accountID: current.accountID, owner: current.owner, mode: current.mode,
                usdc: HyperCoreUSDCAmount("184467440737.09551615"), held: current.held,
                perps: .init(equity: HyperCoreUSDCAmount("-184467440737.09551615", signed: true),
                             withdrawable: HyperCoreUSDCAmount("0"), updatedAt: current.checkedAt),
                requestedAt: current.requestedAt, checkedAt: current.checkedAt)
        }
        let content = HyperCoreBalanceContent(snapshot: snapshot, expired: mode == nil, isLoading: false,
                                             errorMessage: mode == nil ? HyperCoreBalanceError.unavailable.errorDescription : nil,
                                             compact: compact,
                                             history: compact && mode != nil ? [
                                                .init(timestamp: Date().addingTimeInterval(-3_600), value: 58.2),
                                                .init(timestamp: Date(), value: 59.94)
                                             ] : [],
                                             switchAccount: compact ? {} : nil) {
            XCTFail("Rendering must not query balances")
        }
        .padding(20).frame(width: width, alignment: .leading)
        .foregroundStyle(BSmartColor.primaryText).background(BSmartColor.ink)
        .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
        let host = UIHostingController(rootView: content)
        host.safeAreaRegions = []
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.rootViewController = host
        let fitting = host.sizeThatFits(in: CGSize(width: width, height: 1_600))
        window.frame = CGRect(origin: .zero, size: fitting); host.view.frame = window.bounds
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        window.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(fitting.width, width, accuracy: 1)
        if compact {
            XCTAssertGreaterThan(fitting.height, 200)
            XCTAssertLessThan(fitting.height, 360)
        } else {
            XCTAssertGreaterThan(fitting.height, 150); XCTAssertLessThan(fitting.height, 1_100)
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "HyperCore balance \(mode?.rawValue ?? "expired") \(language.rawValue) \(Int(width))"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
