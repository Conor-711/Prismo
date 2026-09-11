import Foundation

// Archival metadata cannot authorize execution; live snapshots must match this exact intent.
struct HyperliquidArchivedOrder: Codable, Equatable, Sendable {
    let accountID: UUID
    let owner: String
    let market: HyperliquidExecutionMarket
    let side: HyperliquidOrderIntent.Side
    let size: String
    let limitPrice: String
    let reduceOnly: Bool
    let cloid: String
    let nonce: UInt64
    let expiresAfter: UInt64

    init(_ order: HyperliquidOrderIntent) throws {
        guard order.builderFee == nil else { throw HyperliquidExecutionError.invalidIntent }
        accountID = order.accountID; owner = order.owner; market = order.market; side = order.side
        size = order.size.wire; limitPrice = order.limitPrice.wire; reduceOnly = order.reduceOnly
        cloid = order.cloid; nonce = order.nonce; expiresAfter = order.expiresAfter
    }

    func restored(wallet: DeviceWalletSummary) throws -> HyperliquidOrderIntent {
        guard wallet.accountID == accountID, wallet.address == owner else { throw FundingJournalError.conflict }
        return try .init(wallet: wallet, market: market, side: side, size: size, limitPrice: limitPrice,
                         reduceOnly: reduceOnly, cloid: cloid, nonce: nonce, expiresAfter: expiresAfter)
    }

    var wallet: DeviceWalletSummary { .init(accountID: accountID, address: owner, recoveryVerified: true) }
}

struct HyperliquidOrderRecord: Codable, Equatable, Sendable, Identifiable {
    enum State: String, Codable, Sendable {
        case review, signing, signed, submitting, uncertain, filled, rejected, cancelled, reconciled
    }
    let id: UUID
    let order: HyperliquidArchivedOrder
    let leverage: Int
    let marginMode: HyperliquidMarketLeverage.Mode
    var state: State
    var signature: String?
    var response: Data?
    var reconciliation: Data? = nil
    var updatedAt: Date

    var acknowledgement: HyperliquidOrderAcknowledgement? {
        guard let response, let intent = try? order.restored(wallet: order.wallet) else { return nil }
        return try? .decode(response, for: intent)
    }

    var reconciledStatus: HyperliquidOrderStatus? {
        guard let reconciliation, let intent = try? order.restored(wallet: order.wallet) else { return nil }
        return try? .decode(reconciliation, order: intent)
    }

    func blocksNewOrder(at now: Date) -> Bool {
        switch state {
        case .submitting, .uncertain: return true
        case .review, .signing, .signed: return now.timeIntervalSince1970 * 1000 <= Double(order.expiresAfter)
        case .filled, .rejected, .cancelled, .reconciled: return false
        }
    }

    func validate(after previous: Self?) throws {
        let intent = try order.restored(wallet: order.wallet)
        guard leverage > 0, leverage <= order.market.maximumLeverage,
              !order.market.isolatedOnly || marginMode == .isolated,
              updatedAt.timeIntervalSince1970.isFinite, updatedAt.timeIntervalSince1970 >= 0,
              response == nil || response!.count <= 8192 else { throw FundingJournalError.integrity }
        if let signature { _ = try HyperliquidOrderCodec.envelope(intent, signature: signature) }
        guard state == .reconciled || reconciliation == nil else { throw FundingJournalError.integrity }
        switch state {
        case .review, .signing, .cancelled:
            guard signature == nil, response == nil else { throw FundingJournalError.integrity }
        case .signed, .submitting, .uncertain:
            guard signature != nil, response == nil else { throw FundingJournalError.integrity }
        case .filled:
            guard signature != nil, case .filled = acknowledgement else { throw FundingJournalError.integrity }
        case .rejected:
            guard signature != nil, case .rejected = acknowledgement else { throw FundingJournalError.integrity }
        case .reconciled:
            guard signature != nil, response == nil, reconciledStatus != nil else { throw FundingJournalError.integrity }
        }
        guard let previous else {
            guard state == .review else { throw FundingJournalError.invalidTransition }
            return
        }
        guard id == previous.id, order == previous.order, leverage == previous.leverage,
              marginMode == previous.marginMode, updatedAt >= previous.updatedAt,
              previous.signature == nil || signature == previous.signature else { throw FundingJournalError.conflict }
        let allowed: [State]
        switch previous.state {
        case .review: allowed = [.signing, .cancelled]
        case .signing: allowed = [.signed]
        case .signed: allowed = [.submitting]
        case .submitting: allowed = [.uncertain, .filled, .rejected, .reconciled]
        case .uncertain: allowed = [.reconciled]
        case .filled, .rejected, .cancelled, .reconciled: allowed = []
        }
        guard allowed.contains(state) else { throw FundingJournalError.invalidTransition }
    }
}
