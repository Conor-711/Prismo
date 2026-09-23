import XCTest
import Security
@testable import BSmart

final class FundingJournalInstallationTests: XCTestCase {
    func testOrphanedLegacyAnchorDoesNotBlockNewInstallAndIsNotOverwritten() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let keychain = InstallationTestKeychain()
        let legacy = try journal(context, keychain: keychain, scoped: false)
        let preview = try await context.preview()
        _ = try await legacy.reserveOrder(id: UUID(), preview: preview,
            wallet: contextWallet, continuousNow: context.clock.instant)
        let oldAnchor = try XCTUnwrap(keychain.snapshot["installation-test.funding-journal.v1"])
        try FileManager.default.removeItem(at: context.directory)

        let fresh = try journal(context, keychain: keychain)
        let records = try await fresh.orderRecords(wallet: contextWallet)
        XCTAssertTrue(records.isEmpty)
        let id = UUID()
        _ = try await fresh.reserveOrder(id: id, preview: preview,
            wallet: contextWallet, continuousNow: context.clock.instant)
        let reopened = try journal(context, keychain: keychain)
        let restored = try await reopened.orderRecords(wallet: contextWallet)
        XCTAssertEqual(restored.map(\.id), [id])
        XCTAssertEqual(keychain.snapshot["installation-test.funding-journal.v1"], oldAnchor)
        XCTAssertEqual(keychain.snapshot.count, 2)
    }

    func testExistingLegacyDatabaseMigratesWithoutLosingPendingOrders() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let keychain = InstallationTestKeychain()
        let legacy = try journal(context, keychain: keychain, scoped: false)
        let preview = try await context.preview(), id = UUID()
        _ = try await legacy.reserveOrder(id: id, preview: preview,
            wallet: contextWallet, continuousNow: context.clock.instant)
        let before = keychain.snapshot
        let upgraded = try journal(context, keychain: keychain)
        let records = try await upgraded.orderRecords(wallet: contextWallet)
        XCTAssertEqual(records.map(\.id), [id])
        XCTAssertEqual(keychain.snapshot, before)
        await expectJournalFailure {
            try await upgraded.reserveOrder(id: UUID(), preview: preview,
                wallet: self.contextWallet, continuousNow: context.clock.instant)
        }
    }

    func testMissingDatabaseWithinSameInstallStillFailsClosed() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let keychain = InstallationTestKeychain()
        let original = try journal(context, keychain: keychain)
        _ = try await original.reserveOrder(id: UUID(), preview: context.preview(),
            wallet: contextWallet, continuousNow: context.clock.instant)
        let before = keychain.snapshot
        // The installation marker is outside the ledger directory.
        try FileManager.default.removeItem(at: ledger(context))
        let reopened = try journal(context, keychain: keychain)
        await expectJournalFailure { try await reopened.orderRecords(wallet: self.contextWallet) }
        XCTAssertEqual(keychain.snapshot, before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ledger(context).appendingPathComponent("transactions.sqlite").path))
    }

    func testReinstallCreatesSeparateScopeAndPreservesPreviousAnchor() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let keychain = InstallationTestKeychain()
        let original = try journal(context, keychain: keychain)
        _ = try await original.reserveOrder(id: UUID(), preview: context.preview(),
            wallet: contextWallet, continuousNow: context.clock.instant)
        let before = keychain.snapshot
        try FileManager.default.removeItem(at: context.directory)
        let fresh = try journal(context, keychain: keychain)
        let records = try await fresh.orderRecords(wallet: contextWallet)
        XCTAssertTrue(records.isEmpty)
        XCTAssertEqual(keychain.snapshot.count, 2)
        for (service, data) in before { XCTAssertEqual(keychain.snapshot[service], data) }
    }

    func testCorruptOrLinkedMarkerCannotRotateAnchor() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let keychain = InstallationTestKeychain()
        let original = try journal(context, keychain: keychain)
        _ = try await original.orderRecords(wallet: contextWallet)
        let before = keychain.snapshot
        let marker = marker(context)
        let data = try Data(contentsOf: marker)
        try Data("invalid".utf8).write(to: marker)
        XCTAssertThrowsError(try journal(context, keychain: keychain))
        try FileManager.default.removeItem(at: marker)
        let target = context.directory.appendingPathComponent("marker-copy")
        try data.write(to: target)
        try FileManager.default.createSymbolicLink(at: marker, withDestinationURL: target)
        XCTAssertThrowsError(try journal(context, keychain: keychain))
        XCTAssertEqual(keychain.snapshot, before)
        XCTAssertEqual(try Data(contentsOf: target), data)
    }

    func testMissingMarkerDoesNotReplaceExistingScopedDatabase() async throws {
        let context = OrderLifecycleContext(); defer { context.cleanup() }
        let keychain = InstallationTestKeychain()
        let original = try journal(context, keychain: keychain)
        _ = try await original.reserveOrder(id: UUID(), preview: context.preview(),
            wallet: contextWallet, continuousNow: context.clock.instant)
        let database = ledger(context).appendingPathComponent("transactions.sqlite")
        let before = try Data(contentsOf: database)
        try FileManager.default.removeItem(at: marker(context))
        let reopened = try journal(context, keychain: keychain)
        await expectJournalFailure { try await reopened.orderRecords(wallet: self.contextWallet) }
        XCTAssertEqual(try Data(contentsOf: database), before)
        XCTAssertEqual(keychain.snapshot.count, 1)
    }

    private var contextWallet: DeviceWalletSummary { HyperliquidTradingFixture.wallet }
    private func ledger(_ context: OrderLifecycleContext) -> URL { context.directory.appendingPathComponent("ledger") }
    private func marker(_ context: OrderLifecycleContext) -> URL { context.directory.appendingPathComponent("installation.json") }
    private func journal(_ context: OrderLifecycleContext, keychain: InstallationTestKeychain,
                         scoped: Bool = true) throws -> FundingTransactionJournal {
        try FundingTransactionJournal(directory: ledger(context), service: "installation-test", keychain: keychain,
            installationMarker: scoped ? marker(context) : nil, clock: { context.clock.now })
    }
}

final class InstallationTestKeychain: WalletKeychainAccess, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: Data] = [:]
    var snapshot: [String: Data] { lock.lock(); defer { lock.unlock() }; return entries }
    func read(_ query: [String: Any]) -> (OSStatus, Data?) {
        lock.lock(); defer { lock.unlock() }
        guard let service = query[kSecAttrService as String] as? String,
              let data = entries[service] else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, data)
    }
    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        guard let service = attributes[kSecAttrService as String] as? String,
              let data = attributes[kSecValueData as String] as? Data else { return errSecParam }
        guard entries[service] == nil else { return errSecDuplicateItem }
        entries[service] = data
        return errSecSuccess
    }
    func update(_ query: [String: Any], values: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        guard let service = query[kSecAttrService as String] as? String,
              let data = values[kSecValueData as String] as? Data else { return errSecParam }
        guard entries[service] != nil else { return errSecItemNotFound }
        entries[service] = data
        return errSecSuccess
    }
}
