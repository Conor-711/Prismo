import Foundation

extension Double {
    var bSmartMarketPrice: String {
        let precision: Int
        switch abs(self) {
        case 1_000...: precision = 1
        case 1...: precision = 2
        case 0.01...: precision = 4
        default: precision = 6
        }
        return formatted(.bSmartDollars.precision(.fractionLength(precision)))
    }

    var bSmartCompactUSD: String {
        switch abs(self) {
        case 1_000_000_000...:
            String(format: "$%.1fB", self / 1_000_000_000)
        case 1_000_000...:
            String(format: "$%.1fM", self / 1_000_000)
        case 1_000...:
            String(format: "$%.1fK", self / 1_000)
        default:
            formatted(.bSmartDollars.precision(.fractionLength(0)))
        }
    }
}

extension FormatStyle where Self == FloatingPointFormatStyle<Double>.Currency {
    static var bSmartDollars: Self {
        .currency(code: "USD").locale(Locale(identifier: "en_US"))
    }
}
