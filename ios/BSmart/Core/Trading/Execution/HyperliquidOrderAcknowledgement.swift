import Foundation

enum HyperliquidOrderAcknowledgement: Equatable, Sendable {
    struct Fill: Equatable, Sendable {
        let orderID: UInt64
        let size: HyperliquidOrderDecimal
        let averagePrice: HyperliquidOrderDecimal
        let isComplete: Bool
    }

    case rejected(String)
    case filled(Fill)

    // A thrown error means unknown, not rejected: reconcile by cloid before any subsequent action.
    static func decode(_ data: Data, for order: HyperliquidOrderIntent) throws -> Self {
        do {
            guard data.count <= 64 * 1024 else { throw HyperliquidExecutionError.invalidAcknowledgement }
            let response = try JSONDecoder().decode(Response.self, from: data)
            if case let .failure(reason) = response.body { return .rejected(reason) }
            guard case let .order(statuses) = response.body, statuses.count == 1 else {
                throw HyperliquidExecutionError.invalidAcknowledgement
            }
            let status = statuses[0]
            if let reason = status.error { return .rejected(reason) }
            guard let fill = status.filled, fill.oid > 0 else {
                throw HyperliquidExecutionError.invalidAcknowledgement
            }
            let size = try HyperliquidOrderDecimal(fill.totalSz)
            let price = try HyperliquidOrderDecimal(fill.avgPx)
            try size.validateSize(decimals: order.market.sizeDecimals)
            guard size <= order.size, price.isPositive,
                  order.side == .buy ? price <= order.limitPrice : price >= order.limitPrice else {
                throw HyperliquidExecutionError.invalidAcknowledgement
            }
            return .filled(.init(orderID: fill.oid, size: size, averagePrice: price, isComplete: size == order.size))
        } catch { throw HyperliquidExecutionError.invalidAcknowledgement }
    }

    private struct Response: Decodable {
        enum Body { case failure(String), order([Status]) }
        let body: Body
        enum CodingKeys: String, CodingKey { case status, response }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .status) {
            case "err":
                let reason = try container.decode(String.self, forKey: .response)
                guard Self.validReason(reason) else { throw HyperliquidExecutionError.invalidAcknowledgement }
                body = .failure(reason)
            case "ok":
                let result = try container.decode(Result.self, forKey: .response)
                guard result.type == "order" else { throw HyperliquidExecutionError.invalidAcknowledgement }
                body = .order(result.data.statuses)
            default: throw HyperliquidExecutionError.invalidAcknowledgement
            }
        }

        static func validReason(_ value: String) -> Bool {
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= 2048
        }
    }

    private struct Result: Decodable {
        let type: String
        let data: Statuses
    }
    private struct Statuses: Decodable { let statuses: [Status] }
    private struct RawFill: Decodable { let totalSz: String; let avgPx: String; let oid: UInt64 }
    private struct Status: Decodable {
        let filled: RawFill?
        let error: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            guard container.allKeys.count == 1, let key = container.allKeys.first else {
                throw HyperliquidExecutionError.invalidAcknowledgement
            }
            switch key.stringValue {
            case "filled": filled = try container.decode(RawFill.self, forKey: key); error = nil
            case "error":
                let reason = try container.decode(String.self, forKey: key)
                guard Response.validReason(reason) else { throw HyperliquidExecutionError.invalidAcknowledgement }
                error = reason; filled = nil
            default: throw HyperliquidExecutionError.invalidAcknowledgement
            }
        }
    }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}
