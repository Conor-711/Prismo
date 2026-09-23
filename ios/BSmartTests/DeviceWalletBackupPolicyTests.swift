import XCTest
@testable import BSmart

final class DeviceWalletBackupPolicyTests: XCTestCase {
    func testEmbeddedRecoveryDoesNotPretendToVerifyMnemonic() {
        let wallet = DeviceWalletSummary(accountID: UUID(), address: HyperliquidOrderTestSupport.wallet.address,
            recoveryVerified: false, provider: .privy)
        XCTAssertTrue(DeviceWalletBackupPolicy.required.permits(wallet))
        XCTAssertFalse(wallet.recoveryVerified)
    }

    func testBackupRemainsTruthfulAndRequiredPolicyRejectsUnbackedWallet() {
        let wallet = DeviceWalletSummary(accountID: UUID(), address: HyperliquidOrderTestSupport.wallet.address,
                                         recoveryVerified: false)
        XCTAssertFalse(DeviceWalletBackupPolicy.required.permits(wallet))
        XCTAssertTrue(DeviceWalletBackupPolicy.optionalForInternalTesting.permits(wallet))
        XCTAssertFalse(wallet.recoveryVerified)
        let backedUp = DeviceWalletSummary(accountID: wallet.accountID, address: wallet.address, recoveryVerified: true)
        XCTAssertTrue(DeviceWalletBackupPolicy.required.permits(backedUp))
        XCTAssertTrue(DeviceWalletBackupPolicy.optionalForInternalTesting.permits(backedUp))
        XCTAssertFalse(DeviceWalletBackupPolicy(allowsUnbackedWallets: false).permits(wallet))
    }

    func testOptionalBackupNeverAcceptsAnInvalidAddress() {
        for address in ["", "0x0", "0x" + String(repeating: "0", count: 40), "0x" + String(repeating: "G", count: 40)] {
            for backedUp in [true, false] {
                let wallet = DeviceWalletSummary(accountID: UUID(), address: address, recoveryVerified: backedUp)
                XCTAssertFalse(DeviceWalletBackupPolicy.optionalForInternalTesting.permits(wallet))
            }
        }
    }

    func testInternalBuildLeaseStillEnforcesAccountAddressAndRevocation() throws {
        XCTAssertEqual(DeviceWalletBackupPolicy.current, .optionalForInternalTesting)
        let wallet = DeviceWalletSummary(accountID: UUID(), address: HyperliquidOrderTestSupport.wallet.address,
                                         recoveryVerified: false)
        let lease = FundingSigningLease(wallet: wallet)
        XCTAssertNoThrow(try lease.check(wallet: wallet))
        XCTAssertThrowsError(try lease.check(wallet: .init(accountID: UUID(), address: wallet.address, recoveryVerified: false)))
        XCTAssertThrowsError(try lease.check(wallet: .init(accountID: wallet.accountID,
            address: "0x" + String(repeating: "1", count: 40), recoveryVerified: false)))
        lease.invalidate()
        XCTAssertThrowsError(try lease.check(wallet: wallet))
        XCTAssertFalse(wallet.recoveryVerified)
    }
}
