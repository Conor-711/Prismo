import Foundation
import Security
import LocalAuthentication
import WalletCore

actor KeychainDeviceWalletVault: DeviceWalletVault, FundingDeviceSigning, HyperliquidDeviceSigning, HyperliquidWithdrawalSigning, UnifiedAccountSetupSigning, HyperliquidLeverageSigning {
    private let service: String
    private let keychain: WalletKeychainAccess
    private let clock: @Sendable () -> Date
    init(service: String = Bundle.main.bundleIdentifier ?? "today.bsmart.ios",
         keychain: WalletKeychainAccess = SystemWalletKeychainAccess(), clock: @escaping @Sendable () -> Date = { Date() }) {
        self.service = service + ".device-owner-wallet.v1"
        self.keychain = keychain
        self.clock = clock
    }

    func summary(accountID: UUID, registeredAddress: String?) throws -> DeviceWalletSummary? {
        guard var record = try locate(accountID: accountID, address: registeredAddress)?.record else { return nil }
        defer { record.eraseTemporaryBytes() }
        return try record.validated(accountID: accountID)
    }

    func create(accountID: UUID) throws -> DeviceWalletSummary {
        if try summary(accountID: accountID, registeredAddress: nil) != nil { throw DeviceWalletError.alreadyExists }
        var entropy = try DeviceWalletCryptography.generateEntropy()
        defer { entropy.resetBytes(in: 0..<entropy.count) }
        var record = DeviceWalletRecord(version: 1, accountID: accountID,
                                       address: try DeviceWalletCryptography.address(entropy: entropy),
                                       entropy: entropy, recoveryVerified: false)
        defer { record.eraseTemporaryBytes() }
        try insert(record)
        return try record.validated(accountID: accountID)
    }

    func recoveryWords(accountID: UUID, address: String) throws -> [String] {
        var record = try require(accountID: accountID, address: address)
        defer { record.eraseTemporaryBytes() }
        return try DeviceWalletCryptography.recoveryWords(entropy: record.entropy)
    }

    func verifyRecovery(accountID: UUID, address: String, phrase: String) throws -> DeviceWalletSummary {
        var recovered = try DeviceWalletCryptography.entropy(phrase: phrase)
        defer { recovered.resetBytes(in: 0..<recovered.count) }
        guard var slot = try locate(accountID: accountID, address: address) else { throw DeviceWalletError.recoveryRequired }
        defer { slot.record.eraseTemporaryBytes() }
        guard try slot.record.validated(accountID: accountID).address == address,
              try DeviceWalletCryptography.address(entropy: recovered) == address,
              slot.record.entropy == recovered else { throw DeviceWalletError.wrongRecovery }
        slot.record.recoveryVerified = true
        var data = try JSONEncoder().encode(slot.record)
        defer { data.resetBytes(in: 0..<data.count) }
        let context = authenticationContext(accountID: accountID)
        var attributes = query(accountID, addressKey: slot.addressKey)
        attributes[kSecUseAuthenticationContext as String] = context
        try checked(keychain.update(attributes, values: [kSecValueData as String: data]))
        return try slot.record.validated(accountID: accountID)
    }

    func restore(accountID: UUID, address: String, phrase: String) throws -> DeviceWalletSummary {
        guard TradingWalletChallenge.validAddress(address) else { throw DeviceWalletError.invalidProof }
        var entropy = try DeviceWalletCryptography.entropy(phrase: phrase)
        defer { entropy.resetBytes(in: 0..<entropy.count) }
        guard try DeviceWalletCryptography.address(entropy: entropy) == address else {
            throw DeviceWalletError.wrongRecovery
        }
        if var existing = try locate(accountID: accountID, address: address) {
            defer { existing.record.eraseTemporaryBytes() }
            if try existing.record.validated(accountID: accountID).address == address {
                return try verifyRecovery(accountID: accountID, address: address, phrase: phrase)
            }
            // Preserve an unbound key from a losing two-device setup race. Never overwrite it.
            guard existing.addressKey == nil else { throw DeviceWalletError.storage }
        }
        var record = DeviceWalletRecord(version: 1, accountID: accountID, address: address,
                                       entropy: entropy, recoveryVerified: true)
        defer { record.eraseTemporaryBytes() }
        try insert(record, addressKey: address)
        return try record.validated(accountID: accountID)
    }

    func signBinding(accountID: UUID, challenge: TradingWalletChallenge) throws -> String {
        var record = try require(accountID: accountID, address: challenge.address)
        defer { record.eraseTemporaryBytes() }
        return try DeviceWalletCryptography.bindingSignature(entropy: record.entropy, challenge: challenge, accountID: accountID)
    }

    func authorizeDeposit(_ permit: FundingAuthorizationPermit, lease: FundingSigningLease) throws -> String {
        let wallet = lease.wallet
        try lease.check(wallet: wallet)
        try permit.plan.validate(wallet: wallet, now: clock())
        guard try FundingConsentPlan(permit.plan).authorizationHash == permit.authorizationHash else {
            throw DeviceWalletError.invalidProof
        }
        var record = try require(accountID: wallet.accountID, address: wallet.address)
        defer { record.eraseTemporaryBytes() }
        let local = try record.validated(accountID: wallet.accountID)
        return try lease.perform(wallet: local) {
            try FundingDeviceCryptography.authorize(plan: permit.plan, entropy: record.entropy, wallet: local, now: clock())
        }
    }

    func signDeposit(_ permit: FundingSigningPermit, transaction: CCTPSourceTransaction,
                     lease: FundingSigningLease) throws -> Data {
        let wallet = lease.wallet
        try lease.check(wallet: wallet)
        guard permit.hasRecordedConsent, permit.accountID == wallet.accountID, permit.owner == wallet.address,
              permit.signingHash == transaction.signingHash else { throw DeviceWalletError.invalidProof }
        try transaction.preflight.validate(wallet: wallet, now: clock())
        var record = try require(accountID: wallet.accountID, address: wallet.address)
        defer { record.eraseTemporaryBytes() }
        let local = try record.validated(accountID: wallet.accountID)
        return try lease.perform(wallet: local) {
            try FundingDeviceCryptography.sign(transaction: transaction, entropy: record.entropy, wallet: local, now: clock())
        }
    }

    private func require(accountID: UUID, address: String) throws -> DeviceWalletRecord {
        guard var record = try locate(accountID: accountID, address: address)?.record else { throw DeviceWalletError.recoveryRequired }
        do {
            guard try record.validated(accountID: accountID).address == address else {
                throw DeviceWalletError.recoveryRequired
            }
            return record
        } catch { record.eraseTemporaryBytes(); throw error }
    }

    func signOrder(_ permit: HyperliquidOrderSigningPermit, lease: FundingSigningLease) throws -> String {
        let wallet = lease.wallet
        try lease.check(wallet: wallet)
        try permit.consume(wallet: wallet, now: clock())
        var record = try require(accountID: wallet.accountID, address: wallet.address)
        defer { record.eraseTemporaryBytes() }
        let local = try record.validated(accountID: wallet.accountID)
        return try lease.perform(wallet: local) {
            // Authentication can take longer than the book TTL. A fresh preflight is mandatory before submission.
            try HyperliquidDeviceCryptography.sign(order: permit.preview.order, entropy: record.entropy, wallet: local, now: clock())
        }
    }

    func signLeverage(_ permit: HyperliquidLeveragePermit, lease: FundingSigningLease) throws -> String {
        let wallet = lease.wallet
        try lease.check(wallet: wallet)
        try permit.consume(wallet: wallet, now: clock())
        var record = try require(accountID: wallet.accountID, address: wallet.address)
        defer { record.eraseTemporaryBytes() }
        let local = try record.validated(accountID: wallet.accountID)
        return try lease.perform(wallet: local) {
            try HyperliquidLeverageCodec.sign(permit.update, entropy: record.entropy, wallet: local, now: clock())
        }
    }

    func signWithdrawal(_ permit: HyperliquidWithdrawalSigningPermit, lease: FundingSigningLease) throws -> String {
        let wallet = lease.wallet
        try lease.check(wallet: wallet)
        try permit.consume(wallet: wallet, now: clock())
        var record = try require(accountID: wallet.accountID, address: wallet.address)
        defer { record.eraseTemporaryBytes() }
        let local = try record.validated(accountID: wallet.accountID)
        return try lease.perform(wallet: local) {
            try HyperliquidWithdrawalCryptography.sign(intent: permit.preview.intent, entropy: record.entropy,
                                                      wallet: local, now: clock())
        }
    }

    func signAcrossStep(_ step: AcrossSigningStep, lease: FundingSigningLease) throws -> String {
        let wallet = lease.wallet
        try lease.check(wallet: wallet)
        var record = try require(accountID: wallet.accountID, address: wallet.address)
        defer { record.eraseTemporaryBytes() }
        let local = try record.validated(accountID: wallet.accountID)
        return try lease.perform(wallet: local) {
            guard record.entropy.count == 32,
                  let hd = HDWallet(entropy: record.entropy, passphrase: ""),
                  let key = hd.getKey(coin: .ethereum, derivationPath: DeviceWalletCryptography.derivationPath),
                  CoinType.ethereum.deriveAddress(privateKey: key).lowercased() == local.address else {
                throw DeviceWalletError.invalidProof
            }
            let value = EthereumMessageSigner.signTypedMessage(privateKey: key, messageJson: step.typedJSON)
            let signature = value.hasPrefix("0x") ? value : "0x" + value
            guard signature.range(of: "^0x[0-9a-fA-F]{130}$", options: .regularExpression) != nil else {
                throw DeviceWalletError.invalidProof
            }
            return signature
        }
    }

    func signUnifiedAccount(_ permit: UnifiedAccountSetupPermit, lease: FundingSigningLease) throws -> String {
        let wallet = lease.wallet
        try lease.check(wallet: wallet)
        try permit.consumeSigning(wallet: wallet, now: clock())
        var record = try require(accountID: wallet.accountID, address: wallet.address)
        defer { record.eraseTemporaryBytes() }
        let local = try record.validated(accountID: wallet.accountID)
        return try lease.perform(wallet: local) {
            try UnifiedAccountSetupCodec.sign(permit.setup, entropy: record.entropy, wallet: local, now: clock())
        }
    }

    private func query(_ accountID: UUID, addressKey: String? = nil) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: accountID.uuidString.lowercased() + (addressKey.map { "." + $0 } ?? ""),
         kSecAttrSynchronizable as String: false]
    }

    private func authenticationContext(accountID: UUID) -> LAContext {
        WalletAuthenticationSession.shared.context(scope: service + "." + accountID.uuidString)
    }

    func userPresenceRequired(accountID: UUID, address: String) async throws -> Bool {
        var record = try require(accountID: accountID, address: address)
        defer { record.eraseTemporaryBytes() }
        return record.userPresenceRequired ?? true
    }

    func setUserPresenceRequired(_ required: Bool, accountID: UUID, address: String) async throws {
        guard var slot = try locate(accountID: accountID, address: address) else {
            throw DeviceWalletError.recoveryRequired
        }
        defer { slot.record.eraseTemporaryBytes() }
        guard try slot.record.validated(accountID: accountID).address == address else {
            throw DeviceWalletError.recoveryRequired
        }
        if (slot.record.userPresenceRequired ?? true) == required { return }
        slot.record.userPresenceRequired = required
        var data = try JSONEncoder().encode(slot.record)
        defer { data.resetBytes(in: 0..<data.count) }
        var attributes = query(accountID, addressKey: slot.addressKey)
        attributes[kSecUseAuthenticationContext as String] = authenticationContext(accountID: accountID)
        // Change the ACL and its metadata atomically in the existing item; never delete a funded key.
        try checked(keychain.update(attributes, values: [kSecValueData as String: data,
            kSecAttrAccessControl as String: try accessControl(requiresPresence: required)]))
        WalletAuthenticationSession.shared.invalidate()
    }

    private func accessControl(requiresPresence: Bool) throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            requiresPresence ? .userPresence : [], &error) else { throw DeviceWalletError.locked }
        return access
    }

    private func locate(accountID: UUID, address: String?) throws -> (record: DeviceWalletRecord, addressKey: String?)? {
        if let address {
            guard TradingWalletChallenge.validAddress(address) else { throw DeviceWalletError.invalidProof }
            if let record = try read(accountID: accountID, addressKey: address) { return (record, address) }
        }
        if let record = try read(accountID: accountID) { return (record, nil) }
        return nil
    }

    private func read(accountID: UUID, addressKey: String? = nil) throws -> DeviceWalletRecord? {
        let context = authenticationContext(accountID: accountID)
        var attributes = query(accountID, addressKey: addressKey)
        attributes[kSecUseAuthenticationContext as String] = context
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, result) = keychain.read(attributes)
        if status == errSecItemNotFound { return nil }
        try checked(status)
        guard var bytes = result, bytes.count <= 2048 else { throw DeviceWalletError.storage }
        defer { bytes.resetBytes(in: 0..<bytes.count) }
        do { return try JSONDecoder().decode(DeviceWalletRecord.self, from: bytes) }
        catch { throw DeviceWalletError.storage }
    }

    private func insert(_ record: DeviceWalletRecord, addressKey: String? = nil) throws {
        let access = try accessControl(requiresPresence: record.userPresenceRequired ?? true)
        var data = try JSONEncoder().encode(record)
        defer { data.resetBytes(in: 0..<data.count) }
        var attributes = query(record.accountID, addressKey: addressKey)
        attributes[kSecAttrAccessControl as String] = access
        attributes[kSecValueData as String] = data
        attributes[kSecAttrLabel as String] = "bSmart device wallet"
        try checked(keychain.add(attributes))
    }

    private func checked(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess: return
        case errSecDuplicateItem: throw DeviceWalletError.alreadyExists
        case errSecUserCanceled:
            WalletAuthenticationSession.shared.invalidate()
            throw DeviceWalletError.cancelled
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecNotAvailable:
            WalletAuthenticationSession.shared.invalidate()
            throw DeviceWalletError.locked
        default: throw DeviceWalletError.storage
        }
    }
}
