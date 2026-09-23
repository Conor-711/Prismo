import Foundation

enum DeviceWalletBackupPolicy: Equatable {
    // Explicit build setting for internal testing; absent or malformed values require backup.
    static let current = DeviceWalletBackupPolicy(
        allowsUnbackedWallets: Bundle.main.object(forInfoDictionaryKey: "BSMART_INTERNAL_OPTIONAL_WALLET_BACKUP") as? String == "YES"
    )

    case required
    case optionalForInternalTesting

    init(allowsUnbackedWallets: Bool) {
        self = allowsUnbackedWallets ? .optionalForInternalTesting : .required
    }

    func permits(_ wallet: DeviceWalletSummary) -> Bool {
        TradingWalletChallenge.validAddress(wallet.address) &&
            (wallet.provider == .privy || wallet.recoveryVerified || self == .optionalForInternalTesting)
    }
}

extension DeviceWalletSummary {
    // Backup status is not an authentication credential and must remain truthful.
    var canAuthorizeTransactions: Bool { DeviceWalletBackupPolicy.current.permits(self) }
}
