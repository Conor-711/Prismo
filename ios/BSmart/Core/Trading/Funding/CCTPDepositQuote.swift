import Foundation

enum CCTPFundingError: Error, LocalizedError, Equatable {
    case unavailable, invalidResponse, expiredQuote, invalidAmount, insufficientNetAmount, invalidPlan

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Deposit fees are unavailable. Try again.".bSmartLocalized
        case .invalidResponse: return "Deposit fee verification failed. No transfer was made.".bSmartLocalized
        case .expiredQuote: return "This fee estimate expired. Refresh it before continuing.".bSmartLocalized
        case .invalidAmount: return "Enter a valid USDC amount with up to six decimals.".bSmartLocalized
        case .insufficientNetAmount: return "At least 1 USDC must remain after the maximum transfer fee.".bSmartLocalized
        case .invalidPlan: return "The deposit details could not be verified. No transfer was made.".bSmartLocalized
        }
    }
}

struct CCTPFeeSchedule: Equatable, Sendable {
    let protocolRateMillionths: UInt64
    let forwardingFeeUnits: UInt64
    let receivedAt: Date

    static let lifetime: TimeInterval = 60

    static func decode(_ data: Data, receivedAt: Date) throws -> Self {
        struct Fee: Decodable {
            struct Forward: Decodable { let low: UInt64; let med: UInt64; let high: UInt64 }
            let finalityThreshold: UInt32
            let minimumFee: Decimal
            let forwardFee: Forward?
        }
        guard data.count <= 16_384, receivedAt.timeIntervalSince1970.isFinite else {
            throw CCTPFundingError.invalidResponse
        }
        let rows: [Fee]
        do { rows = try JSONDecoder().decode([Fee].self, from: data) }
        catch { throw CCTPFundingError.invalidResponse }
        let fast = rows.filter { $0.finalityThreshold == 1000 }
        guard rows.count <= 8, fast.count == 1, let row = fast.first, let forward = row.forwardFee,
              !row.minimumFee.isNaN, row.minimumFee >= 0, row.minimumFee <= 10_000,
              forward.low <= forward.med, forward.med <= forward.high,
              forward.high <= ArbitrumDepositPolicy.maximumBurnUnits else {
            throw CCTPFundingError.invalidResponse
        }
        // Basis points -> millionths, without binary floating-point or silent rounding.
        var scaled = row.minimumFee * 100
        var integral = Decimal()
        NSDecimalRound(&integral, &scaled, 0, .plain)
        guard integral == scaled else { throw CCTPFundingError.invalidResponse }
        let rate = NSDecimalNumber(decimal: integral).uint64Value
        return .init(protocolRateMillionths: rate, forwardingFeeUnits: forward.high, receivedAt: receivedAt)
    }

    func validate(now: Date) throws {
        let age = now.timeIntervalSince(receivedAt)
        guard age.isFinite, age >= 0, age < Self.lifetime else { throw CCTPFundingError.expiredQuote }
        guard protocolRateMillionths <= 1_000_000,
              forwardingFeeUnits <= ArbitrumDepositPolicy.maximumBurnUnits else {
            throw CCTPFundingError.invalidResponse
        }
    }
}

struct CCTPDepositQuote: Equatable, Sendable {
    let schedule: CCTPFeeSchedule
    let amountUnits: UInt64
    let protocolFeeUnits: UInt64
    let forwardingFeeUnits: UInt64
    let maximumFeeUnits: UInt64
    let expiresAt: Date

    // CCTP-only net, before any destination account charges; never a guaranteed HyperCore credit.
    var estimatedCreditUnits: UInt64 { amountUnits - protocolFeeUnits - forwardingFeeUnits }
    var minimumCreditUnits: UInt64 { amountUnits - maximumFeeUnits }
    // Product reserve for account activation, not a protocol deposit minimum or a fee guarantee.
    static let minimumResidualUnits: UInt64 = 1_000_000

    init(amount: String, schedule: CCTPFeeSchedule, now: Date = Date()) throws {
        try schedule.validate(now: now)
        let amountUnits: UInt64
        do {
            amountUnits = try ArbitrumDepositPolicy.validate(amount: amount,
                chainID: ArbitrumDepositPolicy.chainID, tokenAddress: ArbitrumDepositPolicy.nativeUSDC)
        } catch { throw CCTPFundingError.invalidAmount }
        let product = amountUnits.multipliedReportingOverflow(by: schedule.protocolRateMillionths)
        guard !product.overflow else { throw CCTPFundingError.invalidResponse }
        let protocolFee = Self.ceilDivide(product.partialValue, by: 1_000_000)
        let total = protocolFee.addingReportingOverflow(schedule.forwardingFeeUnits)
        guard !total.overflow else { throw CCTPFundingError.invalidResponse }
        let buffer = Self.ceilDivide(total.partialValue, by: 5)
        let ceiling = total.partialValue.addingReportingOverflow(buffer)
        guard !ceiling.overflow, ceiling.partialValue < amountUnits,
              amountUnits - ceiling.partialValue >= Self.minimumResidualUnits else {
            throw CCTPFundingError.insufficientNetAmount
        }
        self.schedule = schedule
        self.amountUnits = amountUnits
        protocolFeeUnits = protocolFee
        forwardingFeeUnits = schedule.forwardingFeeUnits
        maximumFeeUnits = ceiling.partialValue
        expiresAt = schedule.receivedAt.addingTimeInterval(CCTPFeeSchedule.lifetime)
    }

    private static func ceilDivide(_ value: UInt64, by divisor: UInt64) -> UInt64 {
        value / divisor + (value % divisor == 0 ? 0 : 1)
    }
}
