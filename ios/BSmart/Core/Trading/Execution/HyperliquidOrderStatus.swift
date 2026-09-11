import Foundation

struct HyperliquidOrderStatus: Sendable {
    let orderID: UInt64
    let status: String

    static func decode(_ data: Data, order: HyperliquidOrderIntent) throws -> Self {
        guard data.count <= 8192 else { throw HyperliquidExecutionError.invalidAcknowledgement }
        let value = try JSONDecoder().decode(Response.self, from: data)
        guard value.status == "order", let result = value.order else { throw HyperliquidLiveOrderError.recoveryRequired }
        let row = result.order
        guard HyperliquidOrderIdentifier.matches(row.cloid, order.cloid), row.coin == order.market.coin, row.side == (order.side == .buy ? "B" : "A"),
              row.oid > 0, row.reduceOnly == order.reduceOnly, row.tif == "Ioc", !row.isTrigger,
              row.children.isEmpty, try HyperliquidOrderDecimal(row.origSz) == order.size,
              try HyperliquidOrderDecimal(row.limitPx) == order.limitPrice,
              try HyperliquidOrderDecimal(row.sz) <= order.size,
              row.timestamp >= order.nonce.saturatingSubtract(2000), row.timestamp <= order.expiresAfter + 2000,
              result.statusTimestamp >= row.timestamp else { throw HyperliquidExecutionError.invalidAcknowledgement }
        let terminal: Set<String> = ["filled", "canceled", "rejected", "marginCanceled", "openInterestCapCanceled",
            "selfTradeCanceled", "reduceOnlyCanceled", "delistedCanceled", "liquidatedCanceled", "scheduledCancel",
            "tickRejected", "minTradeNtlRejected", "perpMarginRejected", "reduceOnlyRejected", "badAloPxRejected",
            "iocCancelRejected", "badTriggerPxRejected", "marketOrderNoLiquidityRejected", "positionIncreaseAtOpenInterestCapRejected",
            "positionFlipAtOpenInterestCapRejected", "tooAggressiveAtOpenInterestCapRejected", "openInterestIncreaseRejected",
            "insufficientSpotBalanceRejected", "oracleRejected", "perpMaxPositionRejected"]
        guard terminal.contains(result.status) else { throw HyperliquidLiveOrderError.recoveryRequired }
        return .init(orderID: row.oid, status: result.status)
    }

    private struct Response: Decodable { let status: String; let order: Result? }
    private struct Result: Decodable { let order: Row; let status: String; let statusTimestamp: UInt64 }
    private struct Row: Decodable {
        let coin, side, limitPx, sz, origSz, tif: String
        let cloid: String?
        let oid, timestamp: UInt64
        let reduceOnly, isTrigger: Bool
        let children: [FundingRPCValue]
    }
}

private extension UInt64 {
    func saturatingSubtract(_ other: UInt64) -> UInt64 { self >= other ? self - other : 0 }
}
