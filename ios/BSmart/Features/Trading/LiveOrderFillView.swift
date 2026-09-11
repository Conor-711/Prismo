import SwiftUI

struct LiveOrderFillView: View {
    let summary: HyperliquidFillSummary?
    @State private var visibleCount = 20
    @State private var expanded: Bool

    init(summary: HyperliquidFillSummary?, initiallyExpanded: Bool = false) {
        self.summary = summary
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let summary, !summary.fills.isEmpty {
                Label((summary.complete ? "Fills verified" : "Fill details incomplete").bSmartLocalized,
                      systemImage: summary.complete ? "checkmark.circle" : "clock")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(summary.complete ? BSmartColor.brand : BSmartColor.gold)
                metric("Recorded quantity", summary.quantity.wire)
                if let price = summary.averagePrice { metric("Fill average price", price.wire + " USDC") }
                metric(summary.complete ? "Actual fees" : "Recorded fees", summary.fee + " USDC")
                DisclosureGroup(isExpanded: $expanded) {
                    ForEach(summary.fills.prefix(visibleCount)) { fill in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fill.sz + " @ " + fill.px + " USDC").font(.subheadline.monospacedDigit())
                            Text(Date(timeIntervalSince1970: Double(fill.time) / 1000), format: .dateTime.month().day().hour().minute().second())
                                .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                            metric("Fee", fill.fee + " " + fill.feeToken)
                            Text("#\(fill.tid)").font(.caption.monospaced()).foregroundStyle(BSmartColor.secondaryText)
                        }.padding(.vertical, 6)
                    }
                    if visibleCount < summary.fills.count {
                        Button { visibleCount += 20 } label: { Label("More fills".bSmartLocalized, systemImage: "chevron.down") }
                    }
                } label: { Text("Fill details".bSmartLocalized + " (\(summary.fills.count))").font(.subheadline) }
                if !summary.complete {
                    Text("Only verified fills are included. Missing history is not zero fees.".bSmartLocalized)
                        .font(.caption).foregroundStyle(BSmartColor.secondaryText)
                }
            } else {
                Label("Fill details pending".bSmartLocalized, systemImage: "clock")
                    .font(.caption).foregroundStyle(BSmartColor.gold)
                metric("Actual fees", "--")
            }
        }.accessibilityIdentifier("trade.live.fills")
    }

    private func metric(_ key: String, _ value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(key.bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
                Spacer(minLength: 12)
                Text(value).monospacedDigit()
            }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 4) {
                Text(key.bSmartLocalized).foregroundStyle(BSmartColor.secondaryText)
                Text(value).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            }
        }.font(.subheadline)
    }
}
