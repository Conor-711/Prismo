import XCTest
import SwiftUI
@testable import BSmart

@MainActor
final class ArbitrumReceiveLayoutTests: XCTestCase {
    func testEnglishCompactReady() async throws {
        try await render(language: .english, scheme: .dark, width: 320, size: .large, ready: true)
    }
    func testChineseLightReadyAccessibility() async throws {
        try await render(language: .simplifiedChinese, scheme: .light, width: 430, size: .accessibility1, ready: true)
    }
    func testEnglishCompactLockedAccessibility() async throws {
        try await render(language: .english, scheme: .light, width: 320, size: .accessibility1, ready: false)
    }
    private func render(language: AppLanguage, scheme: ColorScheme, width: CGFloat, size: DynamicTypeSize,
                        ready: Bool) async throws {
        let original = BSmartLocalization.language
        BSmartLocalization.configure(language)
        defer { BSmartLocalization.configure(original) }
        let service = ReceiveWalletService()
        let context = ArbitrumReceiveContext(wallet: service.wallet, depositsEnabled: ready, networkConfirmed: true)
        let address = ready ? try WalletReceiveAddress(owner: service.wallet.address) : nil
        let content = ArbitrumReceiveContent(context: context, address: address, isLoading: false, expired: false,
            copied: false, errorMessage: nil, networkConfirmed: .constant(true),
            verify: { XCTFail("Rendering must not request a receiving address") }, copy: { XCTFail("Rendering must not copy") })
            .padding(24).frame(width: width, alignment: .leading)
            .foregroundStyle(BSmartColor.primaryText).background(BSmartColor.ink)
            .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
        let host = UIHostingController(rootView: content)
        host.safeAreaRegions = []
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.rootViewController = host
        let fitting = host.sizeThatFits(in: CGSize(width: width, height: 2_000))
        window.frame = CGRect(origin: .zero, size: fitting); host.view.frame = window.bounds
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        window.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(fitting.width, width, accuracy: 1)
        XCTAssertGreaterThan(fitting.height, 250); XCTAssertLessThan(fitting.height, 1_500)
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
        if let address {
            XCTAssertEqual(try WalletReceiveAddressTests.decode(image), [address.value])
            let label = try XCTUnwrap(addressLabel(in: host.view, address: address.value))
            XCTAssertEqual(label.lineBreakMode, .byCharWrapping)
            XCTAssertEqual(label.text, address.value)
            XCTAssertLessThanOrEqual(label.bounds.width, width - 48)
        } else {
            XCTAssertEqual(try WalletReceiveAddressTests.decode(image), [])
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Receive \(ready ? "ready" : "locked") \(language.rawValue) \(Int(width))"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    private func addressLabel(in view: UIView, address: String) -> UILabel? {
        if let label = view as? UILabel, label.text == address { return label }
        return view.subviews.lazy.compactMap { self.addressLabel(in: $0, address: address) }.first
    }
}
