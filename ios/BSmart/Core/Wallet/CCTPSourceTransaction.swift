import Foundation
import WalletCore

// No arbitrary transaction fields, key access or broadcast. Only the fixed, fresh preflight can enter.
struct CCTPSourceTransaction: Sendable {
    let preflight: CCTPSourcePreflight
    let signingHash: Data
    private let compilerInput: Data

    init(preflight: CCTPSourcePreflight, wallet: DeviceWalletSummary, now: Date) throws {
        try preflight.validate(wallet: wallet, now: now)
        compilerInput = try Self.input(nonce: preflight.nonce, gas: preflight.gasLimit,
                                       price: preflight.maximumFeePerGas, data: preflight.callData)
        signingHash = try Self.digest(compilerInput)
        self.preflight = preflight
    }

    func compile(signature bytes: Data, wallet: DeviceWalletSummary, now: Date) throws -> CCTPSignedSourceTransaction {
        try preflight.validate(wallet: wallet, now: now)
        let raw = try Self.compile(compilerInput, digest: signingHash, signature: bytes, owner: preflight.plan.owner)
        return CCTPSignedSourceTransaction(transaction: self, signature: bytes, raw: raw)
    }

    // Historical journal verification does not create a fresh signing/submission capability.
    static func verifyStored(intent: FundingJournalIntent, signed: FundingJournalRecord.Signed?) throws {
        let input = try storedInput(intent)
        if let signed {
            let raw = try compile(input, digest: intent.signingHash, signature: signed.signature, owner: intent.owner)
            guard signed.raw == raw, signed.hash == FundingHex.encode(Hash.keccak256(data: raw)) else {
                throw FundingJournalError.integrity
            }
        }
    }

    static func archiveSignature(intent: FundingJournalIntent, signature: Data) throws -> FundingJournalRecord.Signed {
        let input = try storedInput(intent)
        let raw = try compile(input, digest: intent.signingHash, signature: signature, owner: intent.owner)
        return .init(signature: signature, raw: raw, hash: FundingHex.encode(Hash.keccak256(data: raw)))
    }

    private static func storedInput(_ intent: FundingJournalIntent) throws -> Data {
        try intent.validate()
        let wallet = DeviceWalletSummary(accountID: intent.accountID, address: intent.owner, recoveryVerified: true)
        let schedule = CCTPFeeSchedule(protocolRateMillionths: intent.protocolRateMillionths,
                                      forwardingFeeUnits: intent.forwardingFeeUnits, receivedAt: intent.feeReceivedAt)
        let quote = try CCTPDepositQuote(amount: FundingQuantity(intent.amountUnits).formatted(decimals: 6),
                                          schedule: schedule, now: intent.planCreatedAt)
        guard let nonce = FundingHex.decode(intent.authorizationNonce) else { throw FundingJournalError.integrity }
        let plan = try CCTPDepositPlan(wallet: wallet, quote: quote, now: intent.planCreatedAt, nonce: nonce)
        guard quote.maximumFeeUnits == intent.maximumCCTPFeeUnits, intent.expiresAt <= quote.expiresAt,
              TimeInterval(plan.validBefore) == intent.authorizationExpiresAt.timeIntervalSince1970,
              try CCTPDepositCodec.callData(plan: plan, wallet: wallet, authorization: intent.authorization,
                                            now: intent.preparedAt) == intent.callData else { throw FundingJournalError.integrity }
        let input = try input(nonce: FundingQuantity(rpc: intent.nonce), gas: FundingQuantity(rpc: intent.gasLimit),
                              price: FundingQuantity(rpc: intent.maximumFeePerGas), data: intent.callData)
        guard try digest(input) == intent.signingHash else { throw FundingJournalError.integrity }
        return input
    }

    private static func input(nonce: FundingQuantity, gas: FundingQuantity, price: FundingQuantity, data: Data) throws -> Data {
        var call = EthereumTransaction.ContractGeneric()
        call.amount = FundingQuantity(0).bigEndianBytes
        call.data = data
        var input = EthereumSigningInput()
        input.chainID = FundingQuantity(UInt64(ArbitrumDepositPolicy.chainID)).bigEndianBytes
        input.txMode = .enveloped
        input.nonce = nonce.bigEndianBytes
        input.gasLimit = gas.bigEndianBytes
        input.maxFeePerGas = price.bigEndianBytes
        input.maxInclusionFeePerGas = FundingQuantity(0).bigEndianBytes
        input.toAddress = CCTPArbitrumRoute.extensionAddress
        input.transaction.contractGeneric = call
        return try input.serializedData()
    }

    private static func digest(_ input: Data) throws -> Data {
        let result = TransactionCompiler.preImageHashes(coinType: .ethereum, txInputData: input)
        let output = try TxCompilerPreSigningOutput(serializedBytes: result)
        guard output.error == .ok, output.dataHash.count == 32 else { throw CCTPFundingError.invalidPlan }
        return output.dataHash
    }

    private static func compile(_ input: Data, digest: Data, signature: Data, owner: String) throws -> Data {
        let signature = try FundingEthereumSignature(signature, encoding: .parity)
        let key = try signature.recover(digest: digest, owner: owner)
        let result = TransactionCompiler.compileWithSignatures(coinType: .ethereum, txInputData: input,
            signatures: DataVector(data: signature.compilerBytes), publicKeys: DataVector(data: key.data))
        let output = try EthereumSigningOutput(serializedBytes: result)
        guard output.error == .ok, output.encoded.first == 2, (100...1_024).contains(output.encoded.count) else {
            throw CCTPFundingError.invalidPlan
        }
        return output.encoded
    }
}

// Constructed only from a verified owner signature over the immutable transaction.
// A locally compiled transaction is neither a submitted payment nor a HyperCore credit.
struct CCTPSignedSourceTransaction: Sendable {
    let transaction: CCTPSourceTransaction
    let signature: Data
    let raw: Data
    let hash: String

    fileprivate init(transaction: CCTPSourceTransaction, signature: Data, raw: Data) {
        self.transaction = transaction
        self.signature = signature
        self.raw = raw
        hash = FundingHex.encode(Hash.keccak256(data: raw))
    }
}
