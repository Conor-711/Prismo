import XCTest
import SwiftUI
@testable import BSmart

@MainActor
final class AccountDeletionLayoutTests: XCTestCase {
    func testUnlinkedWalletEnglishCompact() async throws {
        try await render(stage: nil, language: .english, width: 320, size: .large, scheme: .dark)
    }
    func testPendingChineseLightAccessibility() async throws {
        try await render(stage: .accepted, language: .simplifiedChinese, width: 430, size: .accessibility1, scheme: .light)
    }
    func testCompletedEnglishCompact() async throws {
        try await render(stage: .completed, language: .english, width: 320, size: .large, scheme: .dark)
    }
    func testGoogleDisconnectChineseCompact() async throws {
        try await render(stage: .serverCompleted, language: .simplifiedChinese, width: 320, size: .large, scheme: .dark)
    }

    private func render(stage: AccountDeletionRecord.Stage?, language: AppLanguage, width: CGFloat,
                        size: DynamicTypeSize, scheme: ColorScheme) async throws {
        let original = BSmartLocalization.language
        BSmartLocalization.configure(language)
        defer { BSmartLocalization.configure(original) }
        let fixture = DeletionFixture()
        let client = DeletionAuthClient(fixture.session)
        let account = AccountAccessStore(client: client, storage: RenewalMemoryStorage(fixture.session))
        await account.load()
        var record: AccountDeletionRecord?
        if let stage {
            var value = try fixture.record(); try value.willSubmit()
            try value.received(fixture.receipt(completed: stage != .accepted), now: fixture.now)
            if stage == .completed { try value.finishedProviderDisconnect(); try value.finishedLocalCleanup() }
            record = value
        }
        let storage = DeletionMemoryStorage(record)
        let google = DeletionTestGoogle(); google.failure = AccountDeletionError.providerDisconnectRequired
        let deletion = deletionCoordinator(fixture, storage: storage, google: google)
        let wallet = DeviceWalletStore(service: account, vault: NoDeletionWalletVault())
        let content = NavigationStack { AccountDeletionView() }
            .environmentObject(account).environmentObject(deletion).environmentObject(wallet)
            .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
        let host = UIHostingController(rootView: content)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.rootViewController = host
        window.frame = CGRect(x: 0, y: 0, width: width, height: 820)
        host.view.frame = window.bounds; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(host.view.bounds.width, width, accuracy: 1)
        XCTAssertEqual(wallet.state, .locked)
        XCTAssertEqual(storage.saved?.stage, stage)
        XCTAssertEqual(client.signIns, 0)
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Account deletion \(stage.map { String(describing: $0) } ?? "unlinked") \(language.rawValue) \(Int(width))"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}

private struct NoDeletionWalletVault: DeviceWalletVault {
    private func unexpected() -> DeviceWalletError { XCTFail("Deletion touched wallet vault"); return .storage }
    func summary(accountID: UUID, registeredAddress: String?) async throws -> DeviceWalletSummary? { throw unexpected() }
    func create(accountID: UUID) async throws -> DeviceWalletSummary { throw unexpected() }
    func recoveryWords(accountID: UUID, address: String) async throws -> [String] { throw unexpected() }
    func verifyRecovery(accountID: UUID, address: String, phrase: String) async throws -> DeviceWalletSummary { throw unexpected() }
    func restore(accountID: UUID, address: String, phrase: String) async throws -> DeviceWalletSummary { throw unexpected() }
    func signBinding(accountID: UUID, challenge: TradingWalletChallenge) async throws -> String { throw unexpected() }
}
