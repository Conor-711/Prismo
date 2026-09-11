import XCTest
import SwiftUI
@testable import BSmart

@MainActor
final class CCTPTransferLayoutTests: XCTestCase {
    func testAmountCompactDark() async throws {
        try await render(phase: .amount, language: .english, scheme: .dark, width: 320)
    }

    func testAuthorizationEnglishDark() async throws {
        try await render(phase: .authorization, language: .english, scheme: .dark, width: 393)
    }

    func testNetworkFeeChineseLightAccessibility() async throws {
        try await render(phase: .networkFee, language: .simplifiedChinese, scheme: .light,
                         width: 430, size: .accessibility1)
    }

    func testSignedCompactEnglish() async throws {
        try await render(phase: .signed, language: .english, scheme: .dark, width: 320)
    }

    func testRecordedChineseLightRetainsTransferDetails() async throws {
        try await render(phase: .recorded, language: .simplifiedChinese, scheme: .light, width: 393)
    }

    func testUnknownCompactAccessibility() async throws {
        try await render(phase: .recorded, language: .english, scheme: .dark, width: 320,
                         size: .accessibility1, uncertain: true)
    }

    func testExpiredNetworkFeeChineseDark() async throws {
        try await render(phase: .networkFee, language: .simplifiedChinese, scheme: .dark, width: 393, expired: true)
    }

    private func render(phase: CCTPTransferDisplay.Phase, language: AppLanguage, scheme: ColorScheme,
                        width: CGFloat, size: DynamicTypeSize = .large, uncertain: Bool = false,
                        expired: Bool = false) async throws {
        let rig = try TransferTestRig()
        defer { rig.fixture.context.cleanup() }
        rig.broadcast.uncertain = uncertain
        if phase != .amount { await rig.store.review(amount: "10.123456", wallet: rig.fixture.wallet) }
        if [.networkFee, .signed, .recorded].contains(phase) { await rig.store.authorize() }
        if [.signed, .recorded].contains(phase) { await rig.store.sign() }
        if phase == .recorded { await rig.store.submit() }
        let display = rig.store.display
        XCTAssertEqual(display.phase, phase, rig.store.errorMessage ?? "")
        let now = expired ? try XCTUnwrap(display.expiresAt) : rig.fixture.context.clock.now
        if expired || phase == .recorded { XCTAssertFalse(display.canConfirm(at: now)) }
        let keyReads = rig.fixture.keychain.reads, broadcasts = rig.broadcast.count
        let original = BSmartLocalization.language
        BSmartLocalization.configure(language)
        defer { BSmartLocalization.configure(original) }
        if language == .simplifiedChinese {
            XCTAssertEqual("Source network".bSmartLocalized, "转出网络")
            XCTAssertEqual("Destination account".bSmartLocalized, "转入账户")
            XCTAssertEqual("Confirmation expires in %d s".bSmartLocalized(30), "本次确认将在 30 秒后过期")
        }
        let content = TransferLayoutContent(display: display, now: now)
            .padding(24).frame(width: width, alignment: .leading)
            .foregroundStyle(BSmartColor.primaryText).background(BSmartColor.ink)
            .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
        let host = UIHostingController(rootView: content)
        host.safeAreaRegions = []
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.rootViewController = host
        let fitting = host.sizeThatFits(in: CGSize(width: width, height: 3_000))
        window.frame = CGRect(origin: .zero, size: fitting); host.view.frame = window.bounds
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        window.layoutIfNeeded(); try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(fitting.width, width, accuracy: 1)
        XCTAssertGreaterThan(fitting.height, 200); XCTAssertLessThan(fitting.height, 2_000)
        if let details = display.details {
            let address = try WalletReceiveAddress(owner: details.owner)
            let label = try XCTUnwrap(addressLabel(in: host.view, address: address.value))
            XCTAssertEqual(label.text, address.value)
            XCTAssertEqual(label.lineBreakMode, .byCharWrapping)
            let frame = label.convert(label.bounds, to: host.view)
            XCTAssertGreaterThanOrEqual(frame.minX, 23)
            XCTAssertLessThanOrEqual(frame.maxX, width - 23)
            XCTAssertGreaterThanOrEqual(frame.minY, 0)
            XCTAssertLessThanOrEqual(frame.maxY, fitting.height)
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Transfer \(phase) \(language.rawValue) \(Int(width))\(uncertain ? " unknown" : "")\(expired ? " expired" : "")"
        attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertEqual(rig.fixture.keychain.reads, keyReads, "Rendering must never access wallet keys")
        XCTAssertEqual(rig.broadcast.count, broadcasts, "Rendering must never submit or retry")
    }

    private func addressLabel(in view: UIView, address: String) -> UILabel? {
        if let label = view as? UILabel, label.text == address { return label }
        return view.subviews.lazy.compactMap { self.addressLabel(in: $0, address: address) }.first
    }
}

private struct TransferLayoutContent: View {
    let display: CCTPTransferDisplay
    let now: Date
    @FocusState private var focused: Bool

    var body: some View {
        CCTPTransferContent(display: display, isBusy: false, now: now, errorMessage: nil,
            amount: .constant("10.123456"), amountFocused: $focused,
            primary: { XCTFail("Rendering must not advance the transfer") },
            cancel: { XCTFail("Rendering must not cancel a review") })
    }
}
