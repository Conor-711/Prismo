import XCTest
import Security
import LocalAuthentication
import UIKit
@testable import BSmart

final class FundingDeviceSignerTests: XCTestCase {
    func testUnbackedProtectedAuthorizationAndSourceSignatureAreJournalBoundAndRecoverToOwner() async throws {
        let fixture = try FundingSignerFixture(recoveryVerified: false); defer { fixture.context.cleanup() }
        let journal = try fixture.context.journal()
        let id = UUID()
        _ = try await journal.beginConsent(id: id, plan: fixture.plan, wallet: fixture.wallet)
        let authorizationPermit = try await journal.beginAuthorization(id: id, wallet: fixture.wallet)
        let signer = fixture.signer()
        let lease = FundingSigningLease(wallet: fixture.wallet)
        let authorization = try await signer.authorizeDeposit(authorizationPermit, lease: lease)
        _ = try await journal.recordAuthorization(id: id, signature: authorization, wallet: fixture.wallet)
        let transaction = try await fixture.transaction(authorization: authorization)
        _ = try await journal.reserve(id: id, transaction: transaction, wallet: fixture.wallet)
        let permit = try await journal.beginSigning(id: id, transaction: transaction, wallet: fixture.wallet)
        let signature = try await signer.signDeposit(permit, transaction: transaction, lease: lease)
        let archived = try await journal.recordSignature(id: id, signature: signature, wallet: fixture.wallet)
        XCTAssertEqual(archived.state, .signed)
        XCTAssertEqual(archived.signed?.hash.count, 66)
        XCTAssertEqual(archived.signed?.signature, signature)
        XCTAssertTrue(fixture.keychain.authenticated)
        XCTAssertEqual(fixture.keychain.reads, 2)
        let saved = try JSONDecoder().decode(DeviceWalletRecord.self, from: fixture.keychain.bytes)
        XCTAssertFalse(saved.recoveryVerified)
    }

    func testInvalidatedLeasePreventsKeyAccess() async throws {
        let fixture = try FundingSignerFixture(); defer { fixture.context.cleanup() }
        let permit = try await fixture.authorizationPermit()
        let lease = FundingSigningLease(wallet: fixture.wallet)
        lease.invalidate()
        await expectJournalFailure { try await fixture.signer().authorizeDeposit(permit, lease: lease) }
        XCTAssertEqual(fixture.keychain.reads, 0)
    }

    func testCancellationOrExpiryDuringKeyAccessCannotProduceAuthorization() async throws {
        for change in ["lease", "clock", "task"] {
            let fixture = try FundingSignerFixture(); defer { fixture.context.cleanup() }
            let permit = try await fixture.authorizationPermit()
            let lease = FundingSigningLease(wallet: fixture.wallet)
            fixture.keychain.onRead = {
                switch change {
                case "lease": lease.invalidate()
                case "clock": fixture.context.clock.advance(60)
                default: withUnsafeCurrentTask { $0?.cancel() }
                }
            }
            let result = Task { try await fixture.signer().authorizeDeposit(permit, lease: lease) }
            await expectJournalFailure { try await result.value }
            XCTAssertEqual(fixture.keychain.reads, 1)
            let records = try await fixture.context.journal().consents(wallet: fixture.wallet)
            XCTAssertEqual(records.first?.state, .authorizing)
            XCTAssertNil(records.first?.signature)
        }
    }

    func testProtectedRecordMustMatchTheLeaseIncludingUnchangedBackupState() async throws {
        for change in ["account", "owner", "backup", "locked"] {
            let fixture = try FundingSignerFixture(); defer { fixture.context.cleanup() }
            let permit = try await fixture.authorizationPermit()
            let record = DeviceWalletRecord(version: 1, accountID: change == "account" ? UUID() : fixture.wallet.accountID,
                address: change == "owner" ? PreflightTestFixture.wallet.address : fixture.wallet.address,
                entropy: Data(count: 32), recoveryVerified: change != "backup")
            fixture.keychain.bytes = try JSONEncoder().encode(record)
            if change == "locked" { fixture.keychain.status = errSecInteractionNotAllowed }
            await expectJournalFailure {
                try await fixture.signer().authorizeDeposit(permit, lease: FundingSigningLease(wallet: fixture.wallet))
            }
        }
    }

    func testSourceOnlyLegacyPermitCannotReachDeviceKey() async throws {
        let fixture = try FundingSignerFixture(); defer { fixture.context.cleanup() }
        let journal = try fixture.context.journal()
        let authorization = try FundingDeviceCryptography.authorize(plan: fixture.plan, entropy: Data(count: 32),
            wallet: fixture.wallet, now: fixture.context.clock.now)
        let transaction = try await fixture.transaction(authorization: authorization)
        let id = UUID()
        _ = try await journal.reserve(id: id, transaction: transaction, wallet: fixture.wallet)
        let permit = try await journal.beginSigning(id: id, transaction: transaction, wallet: fixture.wallet)
        await expectJournalFailure {
            try await fixture.signer().signDeposit(permit, transaction: transaction, lease: FundingSigningLease(wallet: fixture.wallet))
        }
        XCTAssertEqual(fixture.keychain.reads, 0)
    }

    func testBackgroundAndProtectedDataNotificationsRevokeLeaseSynchronously() throws {
        for notification in [UIApplication.didEnterBackgroundNotification, UIApplication.protectedDataWillBecomeUnavailableNotification] {
            let wallet = PreflightTestFixture.wallet
            let lease = FundingSigningLease(wallet: wallet)
            XCTAssertNoThrow(try lease.check(wallet: wallet))
            NotificationCenter.default.post(name: notification, object: nil)
            XCTAssertThrowsError(try lease.check(wallet: wallet))
        }
    }

    func testSourceSigningRechecksLeaseAndPreflightAfterProtectedRead() async throws {
        for expiry in [false, true] {
            let fixture = try FundingSignerFixture(); defer { fixture.context.cleanup() }
            let journal = try fixture.context.journal()
            let authorizationPermit = try await fixture.authorizationPermit()
            let lease = FundingSigningLease(wallet: fixture.wallet)
            let signer = fixture.signer()
            let authorization = try await signer.authorizeDeposit(authorizationPermit, lease: lease)
            _ = try await journal.recordAuthorization(id: authorizationPermit.id, signature: authorization, wallet: fixture.wallet)
            let transaction = try await fixture.transaction(authorization: authorization)
            _ = try await journal.reserve(id: authorizationPermit.id, transaction: transaction, wallet: fixture.wallet)
            let permit = try await journal.beginSigning(id: authorizationPermit.id, transaction: transaction, wallet: fixture.wallet)
            fixture.keychain.onRead = {
                if expiry { fixture.context.clock.advance(31) } else { lease.invalidate() }
            }
            await expectJournalFailure { try await signer.signDeposit(permit, transaction: transaction, lease: lease) }
            XCTAssertEqual(fixture.keychain.reads, 2)
            let records = try await journal.records(wallet: fixture.wallet)
            XCTAssertEqual(records.first?.state, .signing)
            XCTAssertNil(records.first?.signed)
        }
    }

    func testLeaseExpiresWithSessionAndRejectsClockRollback() throws {
        for offset in [-1.0, 5, 61] {
            let clock = JournalTestClock()
            let wallet = PreflightTestFixture.wallet
            let lease = FundingSigningLease(wallet: wallet, expiresAt: clock.now.addingTimeInterval(5), clock: { clock.now })
            XCTAssertNoThrow(try lease.check(wallet: wallet))
            clock.advance(offset)
            XCTAssertThrowsError(try lease.check(wallet: wallet))
        }
    }

    func testLeaseCannotExceedContinuousDeadlineWhenWallClockStops() throws {
        for seconds in [5, 60] {
            let clock = JournalTestClock()
            let continuous = CredentialMonotonicTestClock()
            let wallet = PreflightTestFixture.wallet
            let lease = FundingSigningLease(wallet: wallet, clock: { clock.now },
                continuousDeadline: continuous.now.advanced(by: .seconds(seconds)), continuousNow: { continuous.now })
            continuous.advance(seconds - 1)
            XCTAssertNoThrow(try lease.check(wallet: wallet))
            continuous.advance(1)
            XCTAssertThrowsError(try lease.check(wallet: wallet))
        }
    }
}

struct FundingSignerFixture: Sendable {
    let context = FundingJournalTestContext()
    let wallet: DeviceWalletSummary
    let plan: CCTPDepositPlan
    let keychain: FundingSignerKeychain

    init(recoveryVerified: Bool = true) throws {
        // Published zero-entropy BIP39 test vector; never a real wallet or Keychain item.
        wallet = .init(accountID: context.wallet.accountID,
                       address: try DeviceWalletCryptography.address(entropy: Data(count: 32)), recoveryVerified: recoveryVerified)
        let schedule = try CCTPFeeSchedule.decode(Data(CCTPDepositQuoteTests.response.utf8), receivedAt: context.clock.now)
        plan = try .init(wallet: wallet, quote: CCTPDepositQuote(amount: "10", schedule: schedule, now: context.clock.now),
                         now: context.clock.now, nonce: Data(repeating: 17, count: 32))
        keychain = FundingSignerKeychain(bytes: try JSONEncoder().encode(DeviceWalletRecord(version: 1,
            accountID: wallet.accountID, address: wallet.address, entropy: Data(count: 32), recoveryVerified: recoveryVerified)))
    }

    func signer() -> KeychainDeviceWalletVault {
        .init(service: context.service, keychain: keychain, clock: { context.clock.now })
    }

    func authorizationPermit() async throws -> FundingAuthorizationPermit {
        let journal = try context.journal()
        let id = UUID()
        _ = try await journal.beginConsent(id: id, plan: plan, wallet: wallet)
        return try await journal.beginAuthorization(id: id, wallet: wallet)
    }

    func transaction(authorization: String) async throws -> CCTPSourceTransaction {
        let rpc = try PreflightStubRPC(blockTime: context.clock.now, owner: wallet.address)
        let preflight = try await ArbitrumSourcePreflight(rpc: rpc, clock: { context.clock.now })
            .prepare(plan: plan, wallet: wallet, authorization: authorization)
        return try .init(preflight: preflight, wallet: wallet, now: context.clock.now)
    }
}

final class FundingSignerKeychain: WalletKeychainAccess, @unchecked Sendable {
    private let lock = NSLock()
    var onRead: (@Sendable () -> Void)?
    var bytes: Data
    var status = errSecSuccess
    private(set) var reads = 0
    private(set) var authenticated = true
    init(bytes: Data) { self.bytes = bytes }
    func read(_ query: [String: Any]) -> (OSStatus, Data?) {
        lock.lock(); defer { lock.unlock() }
        reads += 1
        let context = query[kSecUseAuthenticationContext as String] as? LAContext
        authenticated = authenticated && context != nil && context?.touchIDAuthenticationAllowableReuseDuration == 0
        onRead?()
        return (status, status == errSecSuccess ? bytes : nil)
    }
    func add(_ attributes: [String: Any]) -> OSStatus { errSecNotAvailable }
    func update(_ query: [String: Any], values: [String: Any]) -> OSStatus { errSecNotAvailable }
}
