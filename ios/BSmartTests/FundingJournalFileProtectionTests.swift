import XCTest
import Security
@testable import BSmart

final class FundingJournalFileProtectionTests: XCTestCase {
    func testInstalledJournalReadOnlyDiagnostic() async throws {
        guard ProcessInfo.processInfo.environment["BSMART_DEVICE_JOURNAL_DIAGNOSTIC"] == "1" else {
            throw XCTSkip("Opt-in device journal diagnostic.")
        }
        let service = "today.bsmart.ios"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service + ".funding-journal.v1",
            kSecAttrAccount as String: "ledger", kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        let (status, data) = SystemWalletKeychainAccess().read(query)
        let anchor = data.flatMap { try? JSONDecoder().decode(FundingJournalAnchor.self, from: $0) }
        let directory = try FundingJournalFiles.applicationDirectory()
        let exists = try FundingJournalFiles(directory: directory).databaseExists()
        let evidence = "keychainStatus=\(status), anchorSequence=\(anchor?.committed.sequence.description ?? "none"), databaseExists=\(exists)"
        let attachment = XCTAttachment(string: evidence)
        attachment.lifetime = .keepAlways
        add(attachment)
        let wallet = DeviceWalletSummary(accountID: UUID(),
            address: "0x0000000000000000000000000000000000000001", recoveryVerified: true)
        do {
            let journal = try FundingTransactionJournal()
            _ = try await journal.orderRecords(wallet: wallet)
            _ = try await journal.nextOrderNonce(wallet: wallet)
            _ = try await FundingTransactionJournal().orderRecords(wallet: wallet)
            XCTAssertTrue(try FundingJournalFiles(directory: directory).databaseExists())
            let (afterStatus, afterData) = SystemWalletKeychainAccess().read(query)
            XCTAssertEqual(afterStatus, status)
            XCTAssertTrue(afterData == data, "Legacy anchor must remain unchanged.")
            let success = XCTAttachment(string: "journalRead=success, nonceRead=success, reopen=success, legacyAnchorUnchanged=true")
            success.lifetime = .keepAlways
            add(success)
        }
        catch { XCTFail("\(evidence), readFailure=\(error)") }
    }

    func testJournalThroughSystemStyleParentAliasKeepsTheSameLedger() async throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let root = context.directory.appendingPathComponent("container", isDirectory: true)
        let alias = context.directory.appendingPathComponent("container-alias", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        let journalDirectory = alias.appendingPathComponent("FundingJournal", isDirectory: true)
        let journal = try FundingTransactionJournal(directory: journalDirectory, service: context.service,
            keychain: context.keychain, clock: { context.clock.now })
        let transaction = try await context.transaction()
        let id = UUID()
        _ = try await journal.reserve(id: id, transaction: transaction, wallet: context.wallet)

        let direct = try FundingTransactionJournal(directory: root.appendingPathComponent("FundingJournal"),
            service: context.service, keychain: context.keychain, clock: { context.clock.now })
        let records = try await direct.records(wallet: context.wallet)
        XCTAssertEqual(records.map(\.intent.id), [id])
        let reopened = try await journal.records(wallet: context.wallet)
        XCTAssertEqual(reopened, records)
    }

    func testDatabaseLeafSymlinkIsStillRejected() throws {
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        try FileManager.default.createDirectory(at: context.directory, withIntermediateDirectories: true)
        let original = context.directory.appendingPathComponent("original.sqlite")
        _ = try FundingJournalDatabase(url: original, mayInitialize: true)
        try FileManager.default.createSymbolicLink(at: context.database, withDestinationURL: original)
        XCTAssertThrowsError(try FundingJournalDatabase(url: context.database, mayInitialize: true))
        XCTAssertNoThrow(try FundingJournalDatabase(url: original, mayInitialize: false))
    }

    func testDeviceProtectionPolicyRejectsMissingWeakerOrUnreadableAttributes() throws {
        let file: [FileAttributeKey: Any] = [.posixPermissions: 0o600,
                                            .protectionKey: FileProtectionType.complete]
        XCTAssertNoThrow(try FundingJournalFiles.validateProtection(file, excludedFromBackup: true,
                                                                    directory: false, requiresDataProtection: true))
        for protection in [nil, FileProtectionType.none, .completeUntilFirstUserAuthentication,
                           .completeUnlessOpen] as [FileProtectionType?] {
            var attributes = file
            attributes[.protectionKey] = protection
            XCTAssertThrowsError(try FundingJournalFiles.validateProtection(attributes, excludedFromBackup: true,
                                                                             directory: false, requiresDataProtection: true))
        }
        for excluded in [nil, false] as [Bool?] {
            XCTAssertThrowsError(try FundingJournalFiles.validateProtection(file, excludedFromBackup: excluded,
                                                                             directory: false, requiresDataProtection: true))
        }
        var accessible = file
        accessible[.posixPermissions] = 0o644
        XCTAssertThrowsError(try FundingJournalFiles.validateProtection(accessible, excludedFromBackup: true,
                                                                         directory: false, requiresDataProtection: true))
    }

    func testDirectoryProtectionAndRawStringBridge() throws {
        let directory: [FileAttributeKey: Any] = [.posixPermissions: 0o700,
                                                 .protectionKey: FileProtectionType.complete.rawValue]
        XCTAssertNoThrow(try FundingJournalFiles.validateProtection(directory, excludedFromBackup: true,
                                                                    directory: true, requiresDataProtection: true))
        XCTAssertThrowsError(try FundingJournalFiles.validateProtection(directory, excludedFromBackup: true,
                                                                         directory: false, requiresDataProtection: true))
        XCTAssertNoThrow(try FundingJournalFiles.validateProtection([.posixPermissions: 0o600], excludedFromBackup: true,
                                                                    directory: false, requiresDataProtection: false))
    }

    func testPhysicalDeviceReportsCompleteProtectionForLedgerDirectoryAndLock() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires physical iOS Data Protection; the simulator cannot prove device protection.")
        #else
        let context = FundingJournalTestContext(); defer { context.cleanup() }
        let journal = try context.journal()
        let transaction = try await context.transaction()
        _ = try await journal.reserve(id: UUID(), transaction: transaction, wallet: context.wallet)
        for (url, directory) in [(context.database, false), (context.directory, true),
                                 (context.directory.appendingPathComponent("journal.lock"), false)] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let excluded = try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
            try FundingJournalFiles.validateProtection(attributes, excludedFromBackup: excluded,
                                                       directory: directory, requiresDataProtection: true)
        }
        #endif
    }
}
