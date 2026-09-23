import Foundation

struct ArbitrumFundingBlock: Equatable, Sendable {
    let number: FundingQuantity
    let hash: String
    let timestamp: Date
    let baseFee: FundingQuantity

    init(_ response: FundingRPCValue, now: Date) throws {
        guard case .object(let fields) = response,
              let number = fields["number"], let hash = fields["hash"],
              let timestamp = fields["timestamp"], let fee = fields["baseFeePerGas"] else {
            throw FundingPreflightError.invalidResponse
        }
        self.number = try FundingQuantity(rpc: number.text())
        self.hash = try hash.text()
        guard FundingHex.decode(self.hash)?.count == 32, !self.hash.dropFirst(2).allSatisfy({ $0 == "0" }),
              self.number > FundingQuantity(0), self.number.uint64 != nil,
              let seconds = try FundingQuantity(rpc: timestamp.text()).uint64, seconds < 4_102_444_800 else {
            throw FundingPreflightError.invalidResponse
        }
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(seconds))
        baseFee = try FundingQuantity(rpc: fee.text())
        guard baseFee > FundingQuantity(0) else { throw FundingPreflightError.invalidResponse }
        try validate(now: now)
    }

    var reference: FundingRPCValue { .object(["blockHash": .string(hash), "requireCanonical": .bool(true)]) }

    func validate(now: Date) throws {
        let age = now.timeIntervalSince(timestamp)
        guard age.isFinite, age >= -15, age < 60 else { throw FundingPreflightError.staleState }
    }
}

struct ArbitrumWalletSnapshot: Equatable, Sendable {
    let accountID: UUID
    let owner: String
    let block: ArbitrumFundingBlock
    let usdc: FundingQuantity
    let eth: FundingQuantity
    let nonce: FundingQuantity
    let extensionAllowance: FundingQuantity
    let burnLimit: FundingQuantity
    let observedCodeHashes: [String: String]
    let checkedAt: Date

    var expiresAt: Date { min(checkedAt.addingTimeInterval(30), block.timestamp.addingTimeInterval(60)) }

    func validate(wallet: DeviceWalletSummary, now: Date) throws {
        guard wallet.accountID == accountID, wallet.address == owner else { throw FundingPreflightError.unsupportedWallet }
        guard now >= checkedAt, now < expiresAt else { throw FundingPreflightError.staleState }
        try block.validate(now: now)
    }
}

struct CCTPSourcePreflight: Sendable {
    let plan: CCTPDepositPlan
    let source: ArbitrumWalletSnapshot
    let authorization: String
    let callData: Data
    let nonce: FundingQuantity
    let estimatedGas: FundingQuantity
    let gasLimit: FundingQuantity
    let gasPrice: FundingQuantity
    let maximumFeePerGas: FundingQuantity
    let maximumNetworkFee: FundingQuantity
    let checkedAt: Date

    var expiresAt: Date { min(source.expiresAt, Date(timeIntervalSince1970: Double(plan.validBefore)), checkedAt.addingTimeInterval(30)) }
    var priorityFee: FundingQuantity { FundingQuantity(0) }
    var sourceValue: FundingQuantity { FundingQuantity(0) }

    func validate(wallet: DeviceWalletSummary, now: Date) throws {
        try plan.validateAuthorization(wallet: wallet, now: now)
        try source.validate(wallet: wallet, now: now)
        guard now >= checkedAt, now < expiresAt, checkedAt >= source.checkedAt, checkedAt >= plan.createdAt,
              source.block.timestamp.timeIntervalSince1970 > TimeInterval(plan.validAfter),
              source.block.timestamp.timeIntervalSince1970 < TimeInterval(plan.validBefore) else {
            throw FundingPreflightError.staleState
        }
        guard nonce == source.nonce, nonce.uint64 != nil else { throw FundingPreflightError.pendingTransaction }
        let amount = FundingQuantity(plan.quote.amountUnits)
        guard source.usdc >= amount else { throw FundingPreflightError.insufficientUSDC }
        guard source.burnLimit >= amount, source.extensionAllowance >= amount else { throw FundingPreflightError.routeChanged }
        let budget = try CCTPSourceGasBudget(estimatedGas: estimatedGas, gasPrice: gasPrice, baseFee: source.block.baseFee)
        guard gasLimit == budget.gasLimit, maximumFeePerGas == budget.maximumFeePerGas,
              maximumNetworkFee == budget.maximumNetworkFee else { throw CCTPFundingError.invalidPlan }
        guard source.eth >= maximumNetworkFee else { throw FundingPreflightError.insufficientETH }
        // Reconstruct at the signing boundary; a successful earlier simulation is not enough.
        let expected = try CCTPDepositCodec.callData(plan: plan, wallet: wallet, authorization: authorization, now: now)
        guard callData == expected else { throw CCTPFundingError.invalidPlan }
    }
}
