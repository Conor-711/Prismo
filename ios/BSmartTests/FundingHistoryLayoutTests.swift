import XCTest
import SwiftUI
@testable import BSmart

@MainActor
final class FundingHistoryLayoutTests: XCTestCase {
    func testEnglishDarkHistoryAtCompactWidth() async throws {
        try await render(language: .english, scheme: .dark, width: 320, textSize: .large)
    }

    func testChineseLightHistoryAtAccessibilitySize() async throws {
        try await render(language: .simplifiedChinese, scheme: .light, width: 430, textSize: .accessibility1)
    }

    func testEnglishSourceReceiptAtCompactWidth() async throws {
        try await render(language: .english, scheme: .dark, width: 320, textSize: .large, observe: true)
    }

    func testChineseSourceReceiptAtAccessibilitySize() async throws {
        try await render(language: .simplifiedChinese, scheme: .light, width: 430, textSize: .accessibility1, observe: true)
    }

    func testEnglishAttestationAtCompactWidth() async throws {
        try await render(language: .english, scheme: .dark, width: 320, textSize: .large, observe: true, attest: true)
    }

    func testChineseAttestationAtAccessibilitySize() async throws {
        try await render(language: .simplifiedChinese, scheme: .light, width: 430, textSize: .accessibility1, observe: true, attest: true)
    }

    func testEnglishForwardingAtCompactWidth() async throws {
        try await render(language: .english, scheme: .dark, width: 320, textSize: .large, observe: true, attest: true, forward: "perps")
    }

    func testChineseSpotFallbackAtAccessibilitySize() async throws {
        try await render(language: .simplifiedChinese, scheme: .light, width: 430, textSize: .accessibility1, observe: true, attest: true, forward: "spot")
    }

    func testEnglishDestinationFeeAtCompactWidth() async throws {
        try await render(language: .english, scheme: .dark, width: 320, textSize: .large, observe: true, attest: true, forward: "fee")
    }

    private func render(language: AppLanguage, scheme: ColorScheme, width: CGFloat, textSize: DynamicTypeSize,
                        observe: Bool = false, attest: Bool = false, forward: String? = nil) async throws {
        let originalLanguage = BSmartLocalization.language
        BSmartLocalization.configure(language)
        defer { BSmartLocalization.configure(originalLanguage) }
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let transaction = try await context.transaction()
        let journal = try context.journal()
        let id = UUID()
        _ = try await context.ready(transaction, id: id, journal: journal)
        if observe {
            context.clock.advance(120)
            let lookup = try await journal.sourceLookup(id: id, wallet: context.wallet)
            let fixture = FundingObservationFixture(record: lookup.record, now: context.clock.now)
            let observer = fixture.observer(rpc: FundingObservationRPC(fixture, overrides: ["block-finalized": fixture.includedBlock]))
            let result = try await observer.observe(lookup, wallet: context.wallet)
            try await journal.recordSourceObservation(result, wallet: context.wallet)
        }
        if attest {
            let lookup = try await journal.attestationLookup(id: id, wallet: context.wallet)
            let rpc = AttesterRPCStub(now: context.clock.now, overrides: forward == nil ? [:] : ["usedNonces(bytes32)": .string(FundingQuantity(1).abi)])
            let evidence = try await context.attester(.complete(AttestationVector.load().proof(), forwardHash: forward == nil ? nil : ForwardVector.load().hash), rpc: rpc)
                .observe(lookup, wallet: context.wallet)
            try await journal.recordAttestation(evidence, wallet: context.wallet)
        }
        if let forward {
            let lookup = try await journal.forwardingLookup(id: id, wallet: context.wallet)
            let result = try await context.forwarder(mode: forward).observe(lookup, wallet: context.wallet)
            try await journal.recordForwarding(result, wallet: context.wallet)
        }
        let history = try await journal.history(wallet: context.wallet)
        let entry = try XCTUnwrap(history.first)
        let content = VStack(alignment: .leading, spacing: 12) {
            Text("Deposit history".bSmartLocalized).font(.title2.bold())
            FundingHistoryRow(entry: entry, expanded: .constant(true), checkSource: { XCTFail("Rendering cannot query") },
                              checkCrossChain: attest ? { XCTFail("Rendering cannot query") } : nil) {
                XCTFail("Rendering cannot cancel")
            }
        }
        .padding(20).frame(width: width, alignment: .leading)
        .background(BSmartColor.ink).foregroundStyle(BSmartColor.primaryText)
        .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, textSize)
        let host = UIHostingController(rootView: content)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.rootViewController = host
        let size = host.sizeThatFits(in: CGSize(width: width, height: 2200))
        window.frame = CGRect(origin: .zero, size: size)
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let identifiers = scrollViews(in: host.view)
        XCTAssertEqual(identifiers.count, forward == nil ? 2 : 3)
        for identifier in identifiers {
            XCTAssertGreaterThan(identifier.bounds.height, 0)
            XCTAssertGreaterThan(identifier.contentSize.width, identifier.bounds.width)
            let end = identifier.contentSize.width - identifier.bounds.width
            identifier.setContentOffset(CGPoint(x: end, y: 0), animated: false)
            XCTAssertEqual(identifier.contentOffset.x, end, accuracy: 1)
            identifier.setContentOffset(.zero, animated: false)
        }
        // Render the actual UIKit-backed scroll view; ImageRenderer can omit its identifier text.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
        XCTAssertEqual(image.size.width, width)
        XCTAssertGreaterThan(image.size.height, 250)
        XCTAssertLessThan(image.size.height, forward == nil ? 1600 : 2200)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Funding history \(forward ?? (attest ? "attestation" : observe ? "receipt" : "signed")) \(language.rawValue) \(Int(width))"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }
}
