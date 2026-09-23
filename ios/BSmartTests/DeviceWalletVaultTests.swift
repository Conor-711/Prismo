import XCTest
import Security
import LocalAuthentication
@testable import BSmart

final class DeviceWalletVaultTests: XCTestCase {
    private let recovery = (Array(repeating: "abandon", count: 23) + ["art"]).joined(separator: " ")
    private let recoveredAddress = "0xf278cf59f82edcf871d630f28ecc8056f25c1cdb"

    func testAuthenticationPolicyUpdatesExistingKeyAndPersistsAcrossInstances() async throws {
        let io = MemoryWalletKeychain(), account = UUID()
        let vault = KeychainDeviceWalletVault(service: "policy-test", keychain: io)
        let original = try await vault.create(accountID: account)
        let words = try await vault.recoveryWords(accountID: account, address: original.address)
        let initial = try await vault.userPresenceRequired(accountID: account, address: original.address)
        XCTAssertTrue(initial)
        try await vault.setUserPresenceRequired(false, accountID: account, address: original.address)
        let reopened = KeychainDeviceWalletVault(service: "policy-test", keychain: io)
        let required = try await reopened.userPresenceRequired(accountID: account, address: original.address)
        XCTAssertFalse(required)
        let saved = try await reopened.summary(accountID: account, registeredAddress: original.address)
        let preserved = try await reopened.recoveryWords(accountID: account, address: original.address)
        XCTAssertEqual(saved, original); XCTAssertEqual(preserved, words); XCTAssertEqual(io.count, 1)
        XCTAssertTrue(io.updatedAccessControl)
        try await reopened.setUserPresenceRequired(true, accountID: account, address: original.address)
        let enabled = try await vault.userPresenceRequired(accountID: account, address: original.address)
        XCTAssertTrue(enabled)
        XCTAssertEqual(io.count, 1)
    }

    func testFailedPolicyUpdateRetainsProtectionAndOriginalKey() async throws {
        let io = MemoryWalletKeychain(), account = UUID()
        let vault = KeychainDeviceWalletVault(service: "policy-failure", keychain: io)
        let original = try await vault.create(accountID: account)
        io.writeStatus = errSecAuthFailed
        do {
            try await vault.setUserPresenceRequired(false, accountID: account, address: original.address)
            XCTFail("Published a failed ACL update")
        } catch DeviceWalletError.locked {}
        io.writeStatus = nil
        let required = try await vault.userPresenceRequired(accountID: account, address: original.address)
        let saved = try await vault.summary(accountID: account, registeredAddress: original.address)
        XCTAssertTrue(required); XCTAssertEqual(saved, original); XCTAssertEqual(io.count, 1)
    }

    func testAuthenticationContextsAreReusedAndInvalidatedAtSecurityBoundaries() {
        let session = WalletAuthenticationSession()
        let first = session.context(scope: "account-a")
        XCTAssertTrue(first === session.context(scope: "account-a"))
        XCTAssertFalse(first === session.context(scope: "account-b"))
        session.invalidate()
        XCTAssertFalse(first === session.context(scope: "account-a"))
        let beforeBackground = session.context(scope: "account-a")
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertFalse(beforeBackground === session.context(scope: "account-a"))
    }

    func testAuthenticationReuseHasFiveMinuteAbsoluteLimitAndRejectsClockRollback() {
        let clock = TradingCheckClock()
        let session = WalletAuthenticationSession(uptime: { clock.now.timeIntervalSince1970 })
        let first = session.context(scope: "account-a")
        clock.advance(wall: 61)
        XCTAssertTrue(first === session.context(scope: "account-a"))
        clock.advance(wall: 238)
        XCTAssertTrue(first === session.context(scope: "account-a"))
        clock.advance(wall: 1)
        let renewed = session.context(scope: "account-a")
        XCTAssertFalse(first === renewed)
        clock.advance(wall: -1)
        XCTAssertFalse(renewed === session.context(scope: "account-a"))
        let beforeLock = session.context(scope: "account-a")
        NotificationCenter.default.post(name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
        XCTAssertFalse(beforeLock === session.context(scope: "account-a"))
    }

    func testPersistedKeyIsRecoveredByNewVaultInstanceAndCannotBeOverwritten() async throws {
        let io = MemoryWalletKeychain()
        let account = UUID()
        let vault = KeychainDeviceWalletVault(service: "isolated-wallet-test", keychain: io)
        let first = try await vault.create(accountID: account)
        XCTAssertFalse(first.recoveryVerified)
        let reopened = KeychainDeviceWalletVault(service: "isolated-wallet-test", keychain: io)
        let loaded = try await reopened.summary(accountID: account, registeredAddress: first.address)
        XCTAssertEqual(loaded, first)
        do { _ = try await reopened.create(accountID: account); XCTFail("Replaced existing key") }
        catch DeviceWalletError.alreadyExists {}
        let words = try await reopened.recoveryWords(accountID: account, address: first.address)
        XCTAssertEqual(words.count, 24)
        let verified = try await reopened.verifyRecovery(accountID: account, address: first.address,
                                                         phrase: words.joined(separator: " "))
        XCTAssertTrue(verified.recoveryVerified)
        let saved = try await vault.summary(accountID: account, registeredAddress: first.address)
        XCTAssertEqual(saved, verified)
        XCTAssertEqual(io.count, 1)
    }

    func testRestoringWinnerPreservesUnboundKeyFromLosingDevice() async throws {
        let io = MemoryWalletKeychain()
        let vault = KeychainDeviceWalletVault(service: "isolated-wallet-test", keychain: io)
        let account = UUID()
        let unbound = try await vault.create(accountID: account)
        let restored = try await vault.restore(accountID: account, address: recoveredAddress, phrase: recovery)
        XCTAssertEqual(restored.address, recoveredAddress)
        XCTAssertTrue(restored.recoveryVerified)
        let original = try await vault.summary(accountID: account, registeredAddress: nil)
        XCTAssertEqual(original, unbound)
        let active = try await vault.summary(accountID: account, registeredAddress: recoveredAddress)
        XCTAssertEqual(active, restored)
        XCTAssertEqual(io.count, 2)
    }

    func testWrongRecoveryNeverCreatesOrUpdatesARecord() async throws {
        let io = MemoryWalletKeychain()
        let vault = KeychainDeviceWalletVault(service: "isolated-wallet-test", keychain: io)
        do {
            _ = try await vault.restore(accountID: UUID(), address: "0x" + String(repeating: "1", count: 40), phrase: recovery)
            XCTFail("Accepted wrong address")
        } catch DeviceWalletError.wrongRecovery {}
        XCTAssertEqual(io.count, 0)
    }

    func testLockedOrCorruptStorageCannotBeMistakenForMissingWallet() async throws {
        let io = MemoryWalletKeychain()
        let vault = KeychainDeviceWalletVault(service: "isolated-wallet-test", keychain: io)
        let account = UUID()
        io.readStatus = errSecInteractionNotAllowed
        do { _ = try await vault.create(accountID: account); XCTFail("Created while locked") }
        catch DeviceWalletError.locked {}
        XCTAssertEqual(io.count, 0)
        io.readStatus = nil
        _ = try await vault.create(accountID: account)
        io.corruptAll()
        do { _ = try await vault.create(accountID: account); XCTFail("Replaced corrupt key") }
        catch DeviceWalletError.storage {}
        XCTAssertEqual(io.count, 1)
    }

    func testWriteFailureAndDuplicateCannotPublishSuccess() async throws {
        for status in [errSecNotAvailable, errSecDuplicateItem] {
            let io = MemoryWalletKeychain()
            io.writeStatus = status
            let vault = KeychainDeviceWalletVault(service: "isolated-wallet-test", keychain: io)
            do { _ = try await vault.create(accountID: UUID()); XCTFail("Reported unsaved wallet") }
            catch { XCTAssertEqual(io.count, 0) }
        }
    }

    func testAccountsHaveSeparateSlotsAndAccessControlIsRequiredOnEveryInsert() async throws {
        let io = MemoryWalletKeychain()
        let vault = KeychainDeviceWalletVault(service: "isolated-wallet-test", keychain: io)
        let a = UUID(), b = UUID()
        let first = try await vault.create(accountID: a)
        let second = try await vault.create(accountID: b)
        XCTAssertNotEqual(first.address, second.address)
        XCTAssertEqual(io.count, 2)
        XCTAssertTrue(io.allWritesProtected)
        XCTAssertTrue(io.allReadsAuthenticated)
        do { _ = try await vault.recoveryWords(accountID: b, address: first.address); XCTFail("Cross-account key access") }
        catch DeviceWalletError.recoveryRequired {}
    }
}

// This only tests persistence semantics/attributes. It is not a device-passcode security test.
private final class MemoryWalletKeychain: WalletKeychainAccess, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    var readStatus: OSStatus?
    var writeStatus: OSStatus?
    private(set) var allWritesProtected = true
    private(set) var allReadsAuthenticated = true
    private(set) var updatedAccessControl = false
    var count: Int { lock.withLock { items.count } }

    func read(_ query: [String: Any]) -> (OSStatus, Data?) {
        lock.withLock {
            allReadsAuthenticated = allReadsAuthenticated && query[kSecUseAuthenticationContext as String] is LAContext
            if let readStatus { return (readStatus, nil) }
            guard let data = items[key(query)] else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, data)
        }
    }
    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.withLock {
            if let writeStatus { return writeStatus }
            let key = key(attributes)
            if items[key] != nil { return errSecDuplicateItem }
            allWritesProtected = allWritesProtected && attributes[kSecAttrAccessControl as String] != nil &&
                attributes[kSecAttrSynchronizable as String] as? Bool == false
            items[key] = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }
    func update(_ query: [String: Any], values: [String: Any]) -> OSStatus {
        lock.withLock {
            if let writeStatus { return writeStatus }
            guard items[key(query)] != nil else { return errSecItemNotFound }
            updatedAccessControl = values[kSecAttrAccessControl as String] != nil
            items[key(query)] = values[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }
    func corruptAll() { lock.withLock { items = items.mapValues { _ in Data("corrupt".utf8) } } }
    private func key(_ attributes: [String: Any]) -> String {
        "\(attributes[kSecAttrService as String] ?? "")/\(attributes[kSecAttrAccount as String] ?? "")"
    }
}
