import Foundation
import WalletCore
import UIKit

protocol FundingDeviceSigning: Sendable {
    func authorizeDeposit(_ permit: FundingAuthorizationPermit, lease: FundingSigningLease) async throws -> String
    func signDeposit(_ permit: FundingSigningPermit, transaction: CCTPSourceTransaction,
                     lease: FundingSigningLease) async throws -> Data
}

// A revocable foreground/account scope, not a replacement for backend identity or Keychain user presence.
final class FundingSigningLease: @unchecked Sendable {
    let wallet: DeviceWalletSummary
    private let lock = NSLock()
    private var active = true
    private let createdAt: Date
    private let expiresAt: Date
    private let clock: @Sendable () -> Date
    private let createdInstant: ContinuousClock.Instant
    private let deadline: ContinuousClock.Instant
    private let continuousNow: @Sendable () -> ContinuousClock.Instant
    private var observers: [NSObjectProtocol] = []

    init(wallet: DeviceWalletSummary, expiresAt: Date? = nil, clock: @escaping @Sendable () -> Date = { Date() },
         continuousDeadline: ContinuousClock.Instant? = nil,
         continuousNow: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.wallet = wallet
        self.clock = clock
        createdAt = clock()
        self.expiresAt = min(expiresAt ?? createdAt.addingTimeInterval(60), createdAt.addingTimeInterval(60))
        self.continuousNow = continuousNow
        createdInstant = continuousNow()
        deadline = min(continuousDeadline ?? createdInstant.advanced(by: .seconds(60)), createdInstant.advanced(by: .seconds(60)))
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.protectedDataWillBecomeUnavailableNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.invalidate()
            })
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func invalidate() { lock.lock(); defer { lock.unlock() }; active = false }

    func check(wallet: DeviceWalletSummary) throws {
        try perform(wallet: wallet) { }
    }

    func perform<T>(wallet expected: DeviceWalletSummary, _ operation: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        try Task.checkCancellation()
        let now = clock()
        let instant = continuousNow()
        guard active, wallet == expected, expected.canAuthorizeTransactions, now >= createdAt, now < expiresAt,
              instant >= createdInstant, instant < deadline else {
            throw DeviceWalletError.accountChanged
        }
        // Invalidation and the short signing operation are ordered. Never hold this lock during user authentication.
        return try operation()
    }
}

enum FundingDeviceCryptography {
    static func authorize(plan: CCTPDepositPlan, entropy: Data, wallet: DeviceWalletSummary, now: Date) throws -> String {
        let json = try CCTPDepositCodec.authorizationJSON(plan: plan, wallet: wallet, now: now)
        let key = try key(entropy: entropy, owner: wallet.address)
        let value = EthereumMessageSigner.signTypedMessage(privateKey: key, messageJson: json)
        let signature = value.hasPrefix("0x") ? value : "0x" + value
        _ = try CCTPDepositCodec.callData(plan: plan, wallet: wallet, authorization: signature, now: now)
        return signature
    }

    static func sign(transaction: CCTPSourceTransaction, entropy: Data, wallet: DeviceWalletSummary, now: Date) throws -> Data {
        try transaction.preflight.validate(wallet: wallet, now: now)
        let key = try key(entropy: entropy, owner: wallet.address)
        guard let signature = key.sign(digest: transaction.signingHash, curve: .secp256k1) else {
            throw DeviceWalletError.invalidProof
        }
        _ = try transaction.compile(signature: signature, wallet: wallet, now: now)
        return signature
    }

    private static func key(entropy: Data, owner: String) throws -> PrivateKey {
        guard entropy.count == 32, let wallet = HDWallet(entropy: entropy, passphrase: ""),
              let key = wallet.getKey(coin: .ethereum, derivationPath: DeviceWalletCryptography.derivationPath),
              CoinType.ethereum.deriveAddress(privateKey: key).lowercased() == owner else {
            throw DeviceWalletError.invalidProof
        }
        return key
    }
}
