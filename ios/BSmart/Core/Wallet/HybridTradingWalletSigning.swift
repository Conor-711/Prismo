import Foundation

extension HybridTradingWalletVault {
    func signAcrossStep(_ step: AcrossSigningStep, lease: FundingSigningLease) async throws -> String {
        if lease.wallet.provider == .device { return try await local.signAcrossStep(step, lease: lease) }
        return try await typed(step.typedJSON, lease: lease)
    }

    func authorizeDeposit(_ permit: FundingAuthorizationPermit, lease: FundingSigningLease) async throws -> String {
        if lease.wallet.provider == .device { return try await local.authorizeDeposit(permit, lease: lease) }
        let wallet = lease.wallet
        try lease.check(wallet: wallet)
        try permit.plan.validate(wallet: wallet, now: clock())
        guard try FundingConsentPlan(permit.plan).authorizationHash == permit.authorizationHash else {
            throw DeviceWalletError.invalidProof
        }
        let json = try CCTPDepositCodec.authorizationJSON(plan: permit.plan, wallet: wallet, now: clock())
        let signature = try await typed(json, lease: lease)
        _ = try CCTPDepositCodec.callData(plan: permit.plan, wallet: wallet, authorization: signature, now: clock())
        return signature
    }

    func signDeposit(_ permit: FundingSigningPermit, transaction: CCTPSourceTransaction,
                     lease: FundingSigningLease) async throws -> Data {
        if lease.wallet.provider == .device { return try await local.signDeposit(permit, transaction: transaction, lease: lease) }
        let wallet = lease.wallet
        try lease.check(wallet: wallet)
        guard permit.hasRecordedConsent, permit.accountID == wallet.accountID, permit.owner == wallet.address,
              permit.signingHash == transaction.signingHash else { throw DeviceWalletError.invalidProof }
        try transaction.preflight.validate(wallet: wallet, now: clock())
        let raw = try await embedded.signDigest(accountID: wallet.accountID, address: wallet.address, digest: transaction.signingHash)
        try lease.check(wallet: wallet)
        let signature = try EmbeddedWalletSignature.parse(raw).compilerBytes
        _ = try transaction.compile(signature: signature, wallet: wallet, now: clock())
        return signature
    }

    func signOrder(_ permit: HyperliquidOrderSigningPermit, lease: FundingSigningLease) async throws -> String {
        if lease.wallet.provider == .device { return try await local.signOrder(permit, lease: lease) }
        try lease.check(wallet: lease.wallet)
        try permit.consume(wallet: lease.wallet, now: clock())
        let order = permit.preview.order
        let signature = try await typed(HyperliquidOrderCodec.typedJSON(order), lease: lease)
        guard clock().timeIntervalSince1970 * 1000 < Double(order.expiresAfter) else { throw DeviceWalletError.invalidProof }
        _ = try HyperliquidOrderCodec.envelope(order, signature: signature)
        return signature
    }

    func signLeverage(_ permit: HyperliquidLeveragePermit, lease: FundingSigningLease) async throws -> String {
        if lease.wallet.provider == .device { return try await local.signLeverage(permit, lease: lease) }
        try lease.check(wallet: lease.wallet)
        try permit.consume(wallet: lease.wallet, now: clock())
        let signature = try await typed(HyperliquidLeverageCodec.typedJSON(permit.update), lease: lease)
        try permit.update.validate(wallet: lease.wallet, now: clock())
        _ = try HyperliquidLeverageCodec.envelope(permit.update, signature: signature)
        return signature
    }

    func signWithdrawal(_ permit: HyperliquidWithdrawalSigningPermit, lease: FundingSigningLease) async throws -> String {
        if lease.wallet.provider == .device { return try await local.signWithdrawal(permit, lease: lease) }
        try lease.check(wallet: lease.wallet)
        try permit.consume(wallet: lease.wallet, now: clock())
        let intent = permit.preview.intent
        let signature = try await typed(HyperliquidWithdrawalCodec.typedJSON(intent), lease: lease)
        let age = clock().timeIntervalSince1970 * 1000 - Double(intent.nonce)
        guard age >= -1000, age < 60_000 else { throw DeviceWalletError.invalidProof }
        _ = try HyperliquidWithdrawalCodec.envelope(intent, signature: signature)
        return signature
    }

    func signUnifiedAccount(_ permit: UnifiedAccountSetupPermit, lease: FundingSigningLease) async throws -> String {
        if lease.wallet.provider == .device { return try await local.signUnifiedAccount(permit, lease: lease) }
        try lease.check(wallet: lease.wallet)
        try permit.consumeSigning(wallet: lease.wallet, now: clock())
        let signature = try await typed(UnifiedAccountSetupCodec.typedJSON(permit.setup), lease: lease)
        try permit.setup.validate(wallet: lease.wallet, now: clock())
        _ = try UnifiedAccountSetupCodec.envelope(permit.setup, signature: signature)
        return signature
    }

    private func typed(_ json: String, lease: FundingSigningLease) async throws -> String {
        let wallet = lease.wallet
        try lease.check(wallet: wallet)
        let raw = try await embedded.signTypedData(accountID: wallet.accountID, address: wallet.address, json: json)
        try lease.check(wallet: wallet)
        return try EmbeddedWalletSignature.legacy(raw)
    }
}
