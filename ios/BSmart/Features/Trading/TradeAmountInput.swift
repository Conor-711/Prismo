import Foundation

struct TradeAmountInput {
    private(set) var text = "0"
    private let fractionDigits: Int

    init(text: String = "0", fractionDigits: Int = 2) {
        self.fractionDigits = min(6, max(0, fractionDigits))
        setExact(text)
    }

    mutating func setExact(_ value: String) {
        guard let decimal = try? HyperliquidOrderDecimal(value), decimal.scale <= fractionDigits,
              decimal.wire.split(separator: ".")[0].count <= 8 else { return }
        text = decimal.wire
    }

    var value: Double { Double(text) ?? 0 }

    mutating func enter(_ key: String) {
        if key == "delete" {
            if !text.isEmpty { text.removeLast() }
            if text.isEmpty { text = "0" }
            return
        }
        if key == "." {
            if !text.contains(".") { text += "." }
            return
        }
        guard key.count == 1, "0123456789".contains(key) else { return }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 2, parts[1].count >= fractionDigits { return }
        if parts.count == 1, parts[0].count >= 8 { return }
        text = text == "0" ? key : text + key
    }

    mutating func set(_ amount: Double) {
        guard amount.isFinite, amount >= 0 else { text = "0"; return }
        let capped = min(amount, 99_999_999.99)
        let cents = Int((capped * 100).rounded(.down))
        text = cents % 100 == 0
            ? "\(cents / 100)"
            : String(format: "%d.%02d", cents / 100, cents % 100)
    }

    static func maximumMargin(balance: Double, leverage: Int, feeRate: Double) -> Double {
        guard balance.isFinite, balance > 0, leverage >= 1, feeRate >= 0 else { return 0 }
        let amount = balance / (1 + Double(leverage) * feeRate)
        return (amount * 100).rounded(.down) / 100
    }

    static func quoteIsCurrent(_ updatedAt: Date, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(updatedAt)
        return age >= -5 && age <= 30
    }
}
