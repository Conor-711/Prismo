import Foundation

struct HyperliquidOrderFill: Codable, Equatable, Sendable, Identifiable {
    let coin, px, sz, side, fee, feeToken, closedPnl, hash: String
    let oid, tid, time: UInt64
    let builderFee, cloid: String?
    var id: UInt64 { tid }

    func validate(order: HyperliquidOrderIntent, orderID: UInt64) throws {
        guard oid == orderID, tid > 0, tid <= 9_007_199_254_740_991,
              coin == order.market.coin, side == (order.side == .buy ? "B" : "A"), feeToken == "USDC",
              time >= (order.nonce >= 2000 ? order.nonce - 2000 : 0), time <= order.expiresAfter + 2000,
              FundingHex.decode(hash)?.count == 32,
              cloid == nil || HyperliquidOrderIdentifier.matches(cloid, order.cloid) else {
            throw HyperliquidExecutionError.invalidAcknowledgement
        }
        let size = try HyperliquidOrderDecimal(sz), price = try HyperliquidOrderDecimal(px)
        try size.validateSize(decimals: order.market.sizeDecimals)
        guard size <= order.size, price.isPositive,
              order.side == .buy ? price <= order.limitPrice : price >= order.limitPrice else {
            throw HyperliquidExecutionError.invalidAcknowledgement
        }
        _ = try HyperliquidSignedDecimal(fee)
        _ = try HyperliquidSignedDecimal(closedPnl)
        // Initial orders never carry a builder. Nonzero builder fees contradict that signed intent.
        guard order.builderFee == nil, try HyperliquidOrderDecimal(builderFee ?? "0").isPositive == false else {
            throw HyperliquidExecutionError.invalidAcknowledgement
        }
    }

    static func decode(_ data: Data, record: HyperliquidOrderRecord) throws -> [Self] {
        guard data.count <= 2_097_152 else { throw HyperliquidExecutionError.invalidAcknowledgement }
        let rows = try JSONDecoder().decode([Self].self, from: data)
        guard rows.count <= 2000, let orderID = record.fillOrderID else {
            throw HyperliquidExecutionError.invalidAcknowledgement
        }
        let order = try record.order.restored(wallet: record.order.wallet)
        // Only this signed order is retained, never the rest of the owner's trading history.
        let matched = rows.filter { $0.oid == orderID || HyperliquidOrderIdentifier.matches($0.cloid, order.cloid) }
        for row in matched { try row.validate(order: order, orderID: orderID) }
        return matched
    }
}

enum HyperliquidOrderIdentifier {
    static func matches(_ response: String?, _ expected: String) -> Bool {
        guard let response, response.hasPrefix("0x") else { return false }
        let hex = String(response.dropFirst(2))
        guard (1...32).contains(hex.utf8.count) else { return false }
        // HyperCore may omit leading zeroes in the response's 128-bit cloid.
        let padded = "0x" + String(repeating: "0", count: 32 - hex.utf8.count) + hex.lowercased()
        guard let bytes = FundingHex.decode(padded), bytes.count == 16 else { return false }
        return bytes == FundingHex.decode(expected)
    }
}

extension HyperliquidOrderRecord {
    var fillOrderID: UInt64? {
        if case .filled(let fill) = acknowledgement { return fill.orderID }
        return reconciledStatus?.orderID
    }

    var expectedFillSize: HyperliquidOrderDecimal? {
        if case .filled(let fill) = acknowledgement { return fill.size }
        if reconciledStatus?.status == "filled" { return try? .init(order.size) }
        return nil
    }
}

struct HyperliquidFillSummary: Sendable {
    let fills: [HyperliquidOrderFill]
    let quantity: HyperliquidOrderDecimal
    let averagePrice: HyperliquidOrderDecimal?
    let fee: String
    let complete: Bool

    init(record: HyperliquidOrderRecord, fills: [HyperliquidOrderFill]) throws {
        guard let oid = record.fillOrderID, fills.count <= 4000 else { throw FundingJournalError.conflict }
        let order = try record.order.restored(wallet: record.order.wallet)
        var unique: [UInt64: HyperliquidOrderFill] = [:]
        for fill in fills {
            try fill.validate(order: order, orderID: oid)
            guard unique[fill.tid] == nil || unique[fill.tid] == fill else { throw FundingJournalError.conflict }
            unique[fill.tid] = fill
        }
        guard unique.count <= 2000 else { throw FundingJournalError.capacity }
        self.fills = unique.values.sorted { $0.time == $1.time ? $0.tid < $1.tid : $0.time < $1.time }
        var size = HyperliquidExactValue(0), notional = HyperliquidExactValue(0)
        var fees = HyperliquidExactValue(0), rebates = HyperliquidExactValue(0)
        for fill in self.fills {
            let amount = HyperliquidExactValue(try .init(fill.sz)), price = HyperliquidExactValue(try .init(fill.px))
            size = try size.adding(amount)
            notional = try notional.adding(amount.multiplied(by: price))
            let signedFee = try HyperliquidSignedDecimal(fill.fee)
            if signedFee.isNegative { rebates = try rebates.adding(.init(signedFee.magnitude)) }
            else { fees = try fees.adding(.init(signedFee.magnitude)) }
        }
        quantity = try size.rounded(decimalPlaces: 18, up: false)
        guard quantity <= (record.expectedFillSize ?? order.size) else { throw FundingJournalError.conflict }
        averagePrice = size.isPositive ? try notional.divided(by: size).rounded(decimalPlaces: 8, up: false) : nil
        let net = try (fees >= rebates ? fees.subtracting(rebates) : rebates.subtracting(fees))
            .rounded(decimalPlaces: 18, up: false)
        fee = (fees < rebates ? "-" : "") + net.wire
        // A short/empty history response is not evidence of zero fills or zero fees.
        complete = quantity.isPositive && record.expectedFillSize == quantity
    }
}
